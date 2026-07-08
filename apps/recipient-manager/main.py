"""
Recipient Manager — FastAPI backend
Replaces SAP BO Publications recipient management with a governed React UI.
"""

import os
import json
import time
from contextlib import asynccontextmanager
from typing import Optional
from fastapi import FastAPI, HTTPException, Query
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse, JSONResponse
from pydantic import BaseModel, EmailStr
from databricks import sql as dbsql
from databricks.sdk import WorkspaceClient

# ── Configuration ──
# Set these via environment variables or app.yaml
CATALOG = os.getenv("CATALOG", "YOUR_CATALOG")
SCHEMA = os.getenv("SCHEMA", "bo_demo")
TABLE = f"{CATALOG}.{SCHEMA}.recipient_config"
AUDIT_TABLE = f"{CATALOG}.{SCHEMA}.delivery_audit_log"


_conn = None

# ── In-memory cache ──
_cached_recipients = None
_cache_time = 0
_cache_ttl = 60  # seconds


def _invalidate_cache():
    global _cached_recipients, _cache_time
    _cached_recipients = None
    _cache_time = 0


def get_connection():
    """Get or reuse a persistent Databricks SQL connection."""
    global _conn
    try:
        if _conn is not None:
            _conn.cursor().execute("SELECT 1")
            return _conn
    except Exception:
        _conn = None

    w = WorkspaceClient()
    _conn = dbsql.connect(
        server_hostname=os.getenv(
            "DATABRICKS_SERVER_HOSTNAME",
            w.config.host.replace("https://", ""),
        ),
        http_path=os.getenv("DATABRICKS_HTTP_PATH"),
        credentials_provider=lambda: w.config.authenticate,
    )
    return _conn


def run_query(sql: str) -> list[dict]:
    """Execute a SQL query and return list of dicts."""
    conn = get_connection()
    cursor = conn.cursor()
    cursor.execute(sql)
    if cursor.description:
        columns = [desc[0] for desc in cursor.description]
        rows = cursor.fetchall()
        return [dict(zip(columns, row)) for row in rows]
    return []


def run_statement(sql: str):
    """Execute a SQL statement (INSERT/UPDATE/DELETE)."""
    conn = get_connection()
    cursor = conn.cursor()
    cursor.execute(sql)


def escape_sql(val) -> str:
    """Escape single quotes for SQL."""
    if val is None:
        return "NULL"
    return str(val).replace("'", "''")


# ── Pydantic models ──
class RecipientCreate(BaseModel):
    recipient_name: str
    email: str
    company: str
    region: str
    report_type: str
    format: str
    filter_column: Optional[str] = "region"
    filter_value: Optional[str] = ""
    is_active: bool = False
    filters: Optional[str] = "[]"


class RecipientUpdate(BaseModel):
    recipient_name: Optional[str] = None
    email: Optional[str] = None
    company: Optional[str] = None
    region: Optional[str] = None
    report_type: Optional[str] = None
    format: Optional[str] = None
    is_active: Optional[bool] = None
    filters: Optional[str] = None
    filter_column: Optional[str] = None
    filter_value: Optional[str] = None


# ── FastAPI app ──
app = FastAPI(title="Recipient Manager")


# ── API Routes ──

def _fetch_recipients() -> list[dict]:
    """Fetch recipients with caching."""
    global _cached_recipients, _cache_time
    now = time.time()
    if _cached_recipients is not None and (now - _cache_time) < _cache_ttl:
        return _cached_recipients

    rows = run_query(f"SELECT * FROM {TABLE} ORDER BY recipient_id")
    for row in rows:
        if "is_active" in row:
            row["is_active"] = bool(row["is_active"])
        if "filters" in row and row["filters"]:
            try:
                row["filters_parsed"] = json.loads(row["filters"])
            except (json.JSONDecodeError, TypeError):
                row["filters_parsed"] = []
        else:
            row["filters_parsed"] = []

    _cached_recipients = rows
    _cache_time = now
    return rows


@app.get("/api/init")
async def get_init():
    """Combined endpoint: recipients + stats + last delivery in one call."""
    import logging
    logger = logging.getLogger("recipient-manager")
    try:
        logger.info("Loading /api/init...")
        recipients = _fetch_recipients()
        stats_recipients = run_query(f"""
            SELECT
                COUNT(*) as total,
                SUM(CASE WHEN is_active THEN 1 ELSE 0 END) as active,
                COUNT(DISTINCT report_type) as report_types,
                COUNT(DISTINCT region) as regions
            FROM {TABLE}
        """)
        audit_stats = run_query(f"""
            SELECT
                COUNT(*) as total_deliveries,
                SUM(CASE WHEN status = 'SUCCESS' THEN 1 ELSE 0 END) as success,
                SUM(CASE WHEN status = 'FAILED' THEN 1 ELSE 0 END) as failed,
                SUM(CASE WHEN status = 'DRY_RUN' THEN 1 ELSE 0 END) as dry_run
            FROM {AUDIT_TABLE}
        """)
        last_delivery = run_query(f"""
            SELECT delivered_at FROM {AUDIT_TABLE}
            ORDER BY delivered_at DESC LIMIT 1
        """)
        last_ts = None
        if last_delivery and last_delivery[0].get("delivered_at"):
            val = last_delivery[0]["delivered_at"]
            last_ts = val.isoformat() if hasattr(val, "isoformat") else str(val)

        return {
            "recipients": recipients,
            "stats": {
                "recipients": stats_recipients[0] if stats_recipients else {},
                "audit": audit_stats[0] if audit_stats else {},
            },
            "last_delivery": last_ts,
        }
    except Exception as e:
        logger.error(f"/api/init failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/api/recipients")
async def get_recipients():
    """Get all recipients."""
    try:
        return {"recipients": _fetch_recipients()}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/api/recipients")
async def create_recipient(r: RecipientCreate):
    """Create a new recipient."""
    try:
        result = run_query(
            f"SELECT COALESCE(MAX(recipient_id), 0) + 1 AS nid FROM {TABLE}"
        )
        nid = int(result[0]["nid"]) if result else 100

        if r.filters and r.filters != "[]":
            filters_json = r.filters
        elif r.filter_column and r.filter_value:
            filters_json = json.dumps(
                [{"column": r.filter_column, "operator": "=", "value": r.filter_value}]
            )
        else:
            filters_json = "[]"

        active_str = "true" if r.is_active else "false"
        fc = escape_sql(r.filter_column or "region")
        fv = escape_sql(r.filter_value or "")

        run_statement(f"""
            INSERT INTO {TABLE} VALUES (
                {nid}, '{escape_sql(r.recipient_name)}', '{escape_sql(r.email)}',
                '{escape_sql(r.company)}', '{escape_sql(r.region)}',
                '{r.report_type}', '{fc}', '{fv}',
                '{escape_sql(filters_json)}', '{r.format}', {active_str},
                current_timestamp()
            )
        """)
        _invalidate_cache()
        return {"id": nid, "message": f"Created recipient {r.recipient_name}"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.put("/api/recipients/{recipient_id}")
async def update_recipient(recipient_id: int, r: RecipientUpdate):
    """Update an existing recipient."""
    try:
        sets = []
        for field, value in r.model_dump(exclude_none=True).items():
            if field == "is_active":
                sets.append(f"{field} = {'true' if value else 'false'}")
            else:
                sets.append(f"{field} = '{escape_sql(value)}'")

        if not sets:
            return {"message": "No changes provided"}

        set_clause = ", ".join(sets)
        run_statement(
            f"UPDATE {TABLE} SET {set_clause} WHERE recipient_id = {recipient_id}"
        )
        _invalidate_cache()
        return {"message": f"Updated recipient {recipient_id}"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.delete("/api/recipients/{recipient_id}")
async def delete_recipient(recipient_id: int):
    """Delete a recipient."""
    try:
        run_statement(
            f"DELETE FROM {TABLE} WHERE recipient_id = {recipient_id}"
        )
        _invalidate_cache()
        return {"message": f"Deleted recipient {recipient_id}"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/api/recipients/{recipient_id}/toggle")
async def toggle_recipient(recipient_id: int):
    """Toggle is_active for a recipient."""
    try:
        rows = run_query(
            f"SELECT is_active FROM {TABLE} WHERE recipient_id = {recipient_id}"
        )
        if not rows:
            raise HTTPException(status_code=404, detail="Recipient not found")

        current = bool(rows[0]["is_active"])
        new_val = "false" if current else "true"
        run_statement(
            f"UPDATE {TABLE} SET is_active = {new_val} WHERE recipient_id = {recipient_id}"
        )
        _invalidate_cache()
        return {"is_active": not current, "message": f"Toggled recipient {recipient_id}"}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/api/recipients/bulk-toggle")
async def bulk_toggle(activate: bool = Query(...)):
    """Bulk activate or deactivate all recipients."""
    try:
        val = "true" if activate else "false"
        run_statement(f"UPDATE {TABLE} SET is_active = {val}")
        _invalidate_cache()
        return {"message": f"All recipients {'activated' if activate else 'deactivated'}"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/api/audit")
async def get_audit_log(
    status: Optional[str] = None,
    limit: int = 100,
    offset: int = 0,
):
    """Get audit log with optional filters."""
    try:
        where = ""
        if status:
            where = f"WHERE status = '{escape_sql(status)}'"

        rows = run_query(f"""
            SELECT delivery_id, recipient_name, email, report_type,
                   region_filter, format, row_count, status,
                   execution_duration_ms, delivered_at
            FROM {AUDIT_TABLE}
            {where}
            ORDER BY delivered_at DESC
            LIMIT {limit} OFFSET {offset}
        """)

        count_result = run_query(
            f"SELECT COUNT(*) as total FROM {AUDIT_TABLE} {where}"
        )
        total = count_result[0]["total"] if count_result else 0

        for row in rows:
            for k, v in row.items():
                if hasattr(v, "isoformat"):
                    row[k] = v.isoformat()

        return {"audit": rows, "total": total}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/api/stats")
async def get_stats():
    """Get dashboard stats."""
    try:
        recipients = run_query(f"""
            SELECT
                COUNT(*) as total,
                SUM(CASE WHEN is_active THEN 1 ELSE 0 END) as active,
                COUNT(DISTINCT report_type) as report_types,
                COUNT(DISTINCT region) as regions
            FROM {TABLE}
        """)
        audit_stats = run_query(f"""
            SELECT
                COUNT(*) as total_deliveries,
                SUM(CASE WHEN status = 'SUCCESS' THEN 1 ELSE 0 END) as success,
                SUM(CASE WHEN status = 'FAILED' THEN 1 ELSE 0 END) as failed,
                SUM(CASE WHEN status = 'DRY_RUN' THEN 1 ELSE 0 END) as dry_run
            FROM {AUDIT_TABLE}
        """)
        return {
            "recipients": recipients[0] if recipients else {},
            "audit": audit_stats[0] if audit_stats else {},
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# ── Serve React frontend ──
FRONTEND_DIR = os.path.join(os.path.dirname(__file__) or ".", "frontend")


@app.get("/{full_path:path}")
async def serve_frontend(full_path: str):
    """Serve the React SPA."""
    if full_path.startswith("api/"):
        raise HTTPException(status_code=404, detail="API route not found")
    return FileResponse(os.path.join(FRONTEND_DIR, "index.html"))
