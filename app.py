import sqlite3
import os
from datetime import date, timedelta
from flask import Flask, render_template, request, redirect, url_for, g, abort

app = Flask(__name__)
DATABASE = os.path.join(app.root_path, 'cloudnine.db')
SCHEMA_FILE = os.path.join(app.root_path, 'schema.sql')

# Anchor "today" inside the seed-data window (deployments 2026-01-01 to 2026-03-20)
SYSTEM_DATE = date(2026, 3, 15)


def get_db():
    db = getattr(g, '_database', None)
    if db is None:
        db = g._database = sqlite3.connect(DATABASE)
        db.row_factory = sqlite3.Row
        db.execute("PRAGMA foreign_keys = ON;")
    return db


@app.teardown_appcontext
def close_connection(exception):
    db = getattr(g, '_database', None)
    if db is not None:
        db.close()


def init_db():
    if os.path.exists(DATABASE):
        os.remove(DATABASE)
    with app.app_context():
        db = get_db()
        with open(SCHEMA_FILE, mode='r') as f:
            db.executescript(f.read())
        db.commit()
        print("Database initialized at:", DATABASE)


# ---------- helpers ----------

def status_class(value):
    """Map a free-form status string to a CSS status-* class."""
    if not value:
        return 'status-neutral'
    v = str(value).lower()
    if v in ('active', 'in-use', 'operational', 'paid', 'finalized', 'confirmed'):
        return 'status-good'
    if v in ('pending', 'maintenance', 'scheduled'):
        return 'status-warn'
    if v in ('terminated',):
        return 'status-orange'
    if v in ('inactive', 'overdue', 'cancelled', 'expired'):
        return 'status-bad'
    if v in ('available', 'completed'):
        return 'status-info'
    return 'status-neutral'


def util_class(pct):
    if pct is None:
        return 'util-low'
    if pct >= 80:
        return 'util-high'
    if pct >= 50:
        return 'util-med'
    return 'util-low'


def normalize_datetime(value):
    if not value:
        return ''
    value = value.replace('T', ' ')
    if len(value) == 16:
        value += ':00'
    return value


@app.context_processor
def inject_helpers():
    return {
        'status_class': status_class,
        'util_class': util_class,
        'system_date': SYSTEM_DATE.strftime('%Y-%m-%d'),
    }


# ---------- 1. Dashboard ----------

@app.route('/')
def dashboard():
    db = get_db()
    today_str = SYSTEM_DATE.strftime('%Y-%m-%d')
    month_start = SYSTEM_DATE.replace(day=1).strftime('%Y-%m-%d')

    total_resources = db.execute("SELECT COUNT(*) FROM resource").fetchone()[0]
    in_use_resources = db.execute("SELECT COUNT(*) FROM resource WHERE status = 'in-use'").fetchone()[0]
    util_pct = round((in_use_resources / total_resources * 100), 1) if total_resources else 0

    active_deployments = db.execute("SELECT COUNT(*) FROM deployment WHERE status = 'active'").fetchone()[0]
    total_deployments = db.execute("SELECT COUNT(*) FROM deployment").fetchone()[0]

    mtd_revenue = db.execute("""
        SELECT COALESCE(SUM(amount), 0) FROM charge
        WHERE chargedAt >= ? AND chargedAt <= ?
    """, (month_start, today_str)).fetchone()[0]

    outstanding = db.execute("""
        SELECT COALESCE(SUM(totalAmount), 0) FROM invoice
        WHERE status = 'pending'
    """).fetchone()[0]

    active_orgs = db.execute("SELECT COUNT(*) FROM organization").fetchone()[0]

    recent_deployments = db.execute("""
        SELECT d.deploymentId, d.deploymentName, d.status, d.priority, d.startedAt,
               c.firstName || ' ' || c.lastName AS clientName, p.projectName
        FROM deployment d
        JOIN reservation r ON d.reservationId = r.reservationId
        JOIN client c ON r.clientId = c.clientId
        LEFT JOIN project p ON d.projectId = p.projectId
        WHERE d.status = 'active'
        ORDER BY d.startedAt DESC
        LIMIT 6
    """).fetchall()

    recent_maintenance = db.execute("""
        SELECT m.maintenanceId, m.maintenanceType, m.scheduledStart, m.actualEnd,
               r.serialNumber, s.name AS staffName
        FROM maintenanceLog m
        JOIN resource r ON m.resourceId = r.resourceId
        JOIN staff s ON m.staffId = s.staffId
        ORDER BY m.scheduledStart DESC
        LIMIT 5
    """).fetchall()

    recent_scaling = db.execute("""
        SELECT se.scalingEventId, se.eventType, se.previousScale, se.newScale, se.triggeredAt,
               d.deploymentName
        FROM scaling_event se
        JOIN deployment d ON se.deploymentId = d.deploymentId
        ORDER BY se.triggeredAt DESC
        LIMIT 5
    """).fetchall()

    kpi = {
        'utilization': util_pct,
        'in_use': in_use_resources,
        'total_resources': total_resources,
        'active_deployments': active_deployments,
        'total_deployments': total_deployments,
        'mtd_revenue': round(mtd_revenue, 2),
        'outstanding': round(outstanding, 2),
        'active_orgs': active_orgs,
    }

    return render_template('dashboard.html',
                           kpi=kpi,
                           deployments=recent_deployments,
                           maintenance=recent_maintenance,
                           scaling=recent_scaling,
                           active_page='dashboard')


# ---------- 2. Infrastructure ----------

@app.route('/infrastructure')
def infrastructure():
    db = get_db()
    regions = db.execute("""
        SELECT r.regionId, r.regionName, r.connectivity, r.regulatoryEnv,
               COUNT(DISTINCT az.zoneId) AS zone_count,
               COUNT(DISTINCT dc.datacenterId) AS dc_count,
               COUNT(DISTINCT res.resourceId) AS resource_count,
               SUM(CASE WHEN res.status = 'in-use' THEN 1 ELSE 0 END) AS in_use_count
        FROM region r
        LEFT JOIN availability_zone az ON r.regionId = az.regionId
        LEFT JOIN data_center dc ON az.zoneId = dc.zoneId
        LEFT JOIN resource res ON dc.datacenterId = res.datacenterId
        GROUP BY r.regionId
        ORDER BY r.regionName
    """).fetchall()

    zones = db.execute("""
        SELECT az.zoneId, az.zoneName, az.redundancyLevel, az.status, az.regionId,
               COUNT(DISTINCT dc.datacenterId) AS dc_count,
               COUNT(res.resourceId) AS resource_count
        FROM availability_zone az
        LEFT JOIN data_center dc ON az.zoneId = dc.zoneId
        LEFT JOIN resource res ON dc.datacenterId = res.datacenterId
        GROUP BY az.zoneId
        ORDER BY az.zoneName
    """).fetchall()

    datacenters = db.execute("""
        SELECT dc.datacenterId, dc.name, dc.country, dc.city, dc.status, dc.zoneId,
               COUNT(res.resourceId) AS resource_count,
               SUM(CASE WHEN res.status = 'in-use' THEN 1 ELSE 0 END) AS in_use_count
        FROM data_center dc
        LEFT JOIN resource res ON dc.datacenterId = res.datacenterId
        GROUP BY dc.datacenterId
        ORDER BY dc.name
    """).fetchall()

    return render_template('infrastructure.html',
                           regions=regions, zones=zones, datacenters=datacenters,
                           active_page='infrastructure')


@app.route('/datacenter/<int:dc_id>')
def datacenter_detail(dc_id):
    db = get_db()
    dc = db.execute("""
        SELECT dc.*, az.zoneName, az.redundancyLevel,
               r.regionName, r.connectivity, r.regulatoryEnv
        FROM data_center dc
        JOIN availability_zone az ON dc.zoneId = az.zoneId
        JOIN region r ON az.regionId = r.regionId
        WHERE dc.datacenterId = ?
    """, (dc_id,)).fetchone()
    if not dc:
        abort(404)

    resources = db.execute("""
        SELECT res.resourceId, res.serialNumber, res.status, res.commissionedAt,
               rt.typeName, rt.category, rt.performanceTier
        FROM resource res
        JOIN resource_type rt ON res.resourceTypeId = rt.resourceTypeId
        WHERE res.datacenterId = ?
        ORDER BY rt.typeName, res.serialNumber
    """, (dc_id,)).fetchall()

    maintenance = db.execute("""
        SELECT m.*, r.serialNumber, s.name AS staffName
        FROM maintenanceLog m
        JOIN resource r ON m.resourceId = r.resourceId
        JOIN staff s ON m.staffId = s.staffId
        WHERE r.datacenterId = ?
        ORDER BY m.scheduledStart DESC
        LIMIT 20
    """, (dc_id,)).fetchall()

    return render_template('datacenter_detail.html',
                           dc=dc, resources=resources, maintenance=maintenance,
                           active_page='infrastructure')


# ---------- 3. Resources ----------

@app.route('/resources')
def resources():
    db = get_db()
    status_filter = request.args.get('status', 'All')
    type_filter = request.args.get('type', 'All')
    region_filter = request.args.get('region', 'All')
    search_query = request.args.get('search', '')
    sort = request.args.get('sort', 'resourceId')
    order = request.args.get('order', 'asc').lower()
    if order not in ('asc', 'desc'):
        order = 'asc'

    allowed_sort = {
        'resourceId': 'res.resourceId',
        'serialNumber': 'res.serialNumber',
        'typeName': 'rt.typeName',
        'status': 'res.status',
        'datacenter': 'dc.name',
        'region': 'r.regionName',
        'commissionedAt': 'res.commissionedAt',
    }
    sort_col = allowed_sort.get(sort, 'res.resourceId')

    sql = """
        SELECT res.resourceId, res.serialNumber, res.status, res.commissionedAt,
               rt.typeName, rt.category, rt.performanceTier, rt.baseHourlyRate,
               dc.datacenterId, dc.name AS datacenterName,
               r.regionName
        FROM resource res
        JOIN resource_type rt ON res.resourceTypeId = rt.resourceTypeId
        JOIN data_center dc ON res.datacenterId = dc.datacenterId
        JOIN availability_zone az ON dc.zoneId = az.zoneId
        JOIN region r ON az.regionId = r.regionId
        WHERE 1=1
    """
    params = []
    if status_filter != 'All':
        sql += " AND res.status = ?"
        params.append(status_filter)
    if type_filter != 'All':
        sql += " AND rt.typeName = ?"
        params.append(type_filter)
    if region_filter != 'All':
        sql += " AND r.regionName = ?"
        params.append(region_filter)
    if search_query:
        sql += " AND (res.serialNumber LIKE ? OR dc.name LIKE ? OR rt.typeName LIKE ?)"
        s = f'%{search_query}%'
        params.extend([s, s, s])
    sql += f" ORDER BY {sort_col} {order}"

    rows = db.execute(sql, params).fetchall()

    types = db.execute("SELECT typeName FROM resource_type ORDER BY typeName").fetchall()
    regions = db.execute("SELECT regionName FROM region ORDER BY regionName").fetchall()
    statuses = ['in-use', 'available', 'maintenance']

    return render_template('resources.html',
                           resources=rows, types=types, regions=regions, statuses=statuses,
                           active_page='resources')


@app.route('/resource/<int:resource_id>')
def resource_detail(resource_id):
    db = get_db()
    res = db.execute("""
        SELECT res.*, rt.typeName, rt.category, rt.performanceTier, rt.baseHourlyRate, rt.maxCapacity,
               dc.datacenterId, dc.name AS datacenterName, dc.country, dc.city,
               az.zoneId, az.zoneName, az.redundancyLevel,
               r.regionId, r.regionName, r.regulatoryEnv
        FROM resource res
        JOIN resource_type rt ON res.resourceTypeId = rt.resourceTypeId
        JOIN data_center dc ON res.datacenterId = dc.datacenterId
        JOIN availability_zone az ON dc.zoneId = az.zoneId
        JOIN region r ON az.regionId = r.regionId
        WHERE res.resourceId = ?
    """, (resource_id,)).fetchone()
    if not res:
        abort(404)

    components = db.execute("""
        SELECT * FROM resource_component WHERE parentResourceId = ?
        ORDER BY componentId
    """, (resource_id,)).fetchall()

    current_deployment = db.execute("""
        SELECT d.deploymentId, d.deploymentName, d.status, d.startedAt,
               c.firstName || ' ' || c.lastName AS clientName
        FROM deployment_resource dr
        JOIN deployment d ON dr.deploymentId = d.deploymentId
        JOIN reservation rv ON d.reservationId = rv.reservationId
        JOIN client c ON rv.clientId = c.clientId
        WHERE dr.resourceId = ? AND dr.deallocatedAt IS NULL
        ORDER BY dr.allocatedAt DESC
        LIMIT 1
    """, (resource_id,)).fetchone()

    deployment_history = db.execute("""
        SELECT d.deploymentId, d.deploymentName, d.status,
               dr.allocatedAt, dr.deallocatedAt, dr.usageHours
        FROM deployment_resource dr
        JOIN deployment d ON dr.deploymentId = d.deploymentId
        WHERE dr.resourceId = ?
        ORDER BY dr.allocatedAt DESC
    """, (resource_id,)).fetchall()

    maintenance = db.execute("""
        SELECT m.*, s.name AS staffName
        FROM maintenanceLog m
        JOIN staff s ON m.staffId = s.staffId
        WHERE m.resourceId = ?
        ORDER BY m.scheduledStart DESC
    """, (resource_id,)).fetchall()

    access = db.execute("""
        SELECT al.*, c.firstName || ' ' || c.lastName AS clientName
        FROM accessLog al
        JOIN client c ON al.clientId = c.clientId
        WHERE al.resourceId = ?
        ORDER BY al.loggedAt DESC
        LIMIT 20
    """, (resource_id,)).fetchall()

    return render_template('resource_detail.html',
                           res=res, components=components,
                           current=current_deployment, history=deployment_history,
                           maintenance=maintenance, access=access,
                           active_page='resources')


# ---------- 4. Organizations ----------

@app.route('/organizations')
def organizations():
    db = get_db()
    sort = request.args.get('sort', 'orgName')
    order = request.args.get('order', 'asc').lower()
    if order not in ('asc', 'desc'):
        order = 'asc'
    allowed = {
        'orgId': 'o.orgId',
        'orgName': 'o.orgName',
        'industry': 'o.industry',
        'creditRating': 'o.creditRating',
        'team_count': 'team_count',
        'client_count': 'client_count',
        'total_spend': 'total_spend',
    }
    sort_col = allowed.get(sort, 'o.orgName')

    search = request.args.get('search', '')
    sql = f"""
        SELECT o.orgId, o.orgName, o.industry, o.contactEmail, o.creditRating, o.createdAt,
               COUNT(DISTINCT t.teamId) AS team_count,
               COUNT(DISTINCT c.clientId) AS client_count,
               COALESCE((SELECT SUM(ch.amount)
                          FROM billing_account ba
                          LEFT JOIN charge ch ON ba.billingAccountId = ch.billingAccountId
                          WHERE ba.orgId = o.orgId), 0) AS total_spend
        FROM organization o
        LEFT JOIN team t ON o.orgId = t.orgId
        LEFT JOIN client c ON o.orgId = c.orgId
        {('WHERE o.orgName LIKE ? OR o.industry LIKE ?' if search else '')}
        GROUP BY o.orgId
        ORDER BY {sort_col} {order}
    """
    params = [f'%{search}%', f'%{search}%'] if search else []
    rows = db.execute(sql, params).fetchall()
    return render_template('organizations.html', orgs=rows, active_page='organizations')


@app.route('/organization/<int:org_id>')
def organization_detail(org_id):
    db = get_db()
    org = db.execute("SELECT * FROM organization WHERE orgId = ?", (org_id,)).fetchone()
    if not org:
        abort(404)
    teams = db.execute("""
        SELECT t.*, COUNT(c.clientId) AS member_count
        FROM team t
        LEFT JOIN client c ON t.teamId = c.teamId
        WHERE t.orgId = ?
        GROUP BY t.teamId
        ORDER BY t.teamName
    """, (org_id,)).fetchall()
    clients = db.execute("""
        SELECT c.*, t.teamName
        FROM client c
        LEFT JOIN team t ON c.teamId = t.teamId
        WHERE c.orgId = ?
        ORDER BY c.lastName, c.firstName
    """, (org_id,)).fetchall()
    accounts = db.execute("""
        SELECT ba.*,
               COALESCE((SELECT SUM(amount) FROM charge WHERE billingAccountId = ba.billingAccountId), 0) AS total_charges
        FROM billing_account ba
        WHERE ba.orgId = ?
    """, (org_id,)).fetchall()
    total_spend = sum((a['total_charges'] or 0) for a in accounts)
    return render_template('organization_detail.html',
                           org=org, teams=teams, clients=clients,
                           accounts=accounts, total_spend=total_spend,
                           active_page='organizations')


# ---------- 5. Clients ----------

@app.route('/clients')
def clients():
    db = get_db()
    sort = request.args.get('sort', 'lastName')
    order = request.args.get('order', 'asc').lower()
    if order not in ('asc', 'desc'):
        order = 'asc'
    allowed = {
        'clientId': 'c.clientId',
        'lastName': 'c.lastName',
        'firstName': 'c.firstName',
        'email': 'c.email',
        'clientType': 'c.clientType',
        'org': 'orgName',
        'team': 'teamName',
    }
    sort_col = allowed.get(sort, 'c.lastName')

    search = request.args.get('search', '')
    type_filter = request.args.get('type', 'All')

    sql = f"""
        SELECT c.clientId, c.firstName, c.lastName, c.email, c.role, c.clientType, c.createdAt,
               o.orgId, o.orgName, t.teamId, t.teamName,
               (SELECT COUNT(*) FROM project WHERE clientId = c.clientId) AS project_count,
               (SELECT COUNT(*) FROM reservation WHERE clientId = c.clientId) AS resv_count
        FROM client c
        LEFT JOIN organization o ON c.orgId = o.orgId
        LEFT JOIN team t ON c.teamId = t.teamId
        WHERE 1=1
    """
    params = []
    if search:
        sql += " AND (c.firstName LIKE ? OR c.lastName LIKE ? OR c.email LIKE ? OR o.orgName LIKE ?)"
        s = f'%{search}%'
        params.extend([s, s, s, s])
    if type_filter != 'All':
        sql += " AND c.clientType = ?"
        params.append(type_filter)
    sql += f" ORDER BY {sort_col} {order}"
    rows = db.execute(sql, params).fetchall()

    types = db.execute("SELECT DISTINCT clientType FROM client ORDER BY clientType").fetchall()
    return render_template('clients.html', clients=rows, types=types, active_page='clients')


@app.route('/client/<int:client_id>')
def client_detail(client_id):
    db = get_db()
    client = db.execute("""
        SELECT c.*, o.orgName, t.teamName
        FROM client c
        LEFT JOIN organization o ON c.orgId = o.orgId
        LEFT JOIN team t ON c.teamId = t.teamId
        WHERE c.clientId = ?
    """, (client_id,)).fetchone()
    if not client:
        abort(404)
    projects = db.execute("SELECT * FROM project WHERE clientId = ? ORDER BY createdAt DESC", (client_id,)).fetchall()
    reservations = db.execute("""
        SELECT r.*, p.projectName
        FROM reservation r
        LEFT JOIN project p ON r.projectId = p.projectId
        WHERE r.clientId = ?
        ORDER BY r.startTime DESC
    """, (client_id,)).fetchall()
    credentials = db.execute("""
        SELECT * FROM credential WHERE clientId = ? ORDER BY createdAt DESC
    """, (client_id,)).fetchall()
    access = db.execute("""
        SELECT al.*, r.serialNumber
        FROM accessLog al
        JOIN resource r ON al.resourceId = r.resourceId
        WHERE al.clientId = ?
        ORDER BY al.loggedAt DESC
        LIMIT 20
    """, (client_id,)).fetchall()
    return render_template('client_detail.html',
                           client=client, projects=projects, reservations=reservations,
                           credentials=credentials, access=access,
                           active_page='clients')


# ---------- 6. Projects ----------

@app.route('/projects')
def projects():
    db = get_db()
    search = request.args.get('search', '')
    sql = """
        SELECT p.projectId, p.projectName, p.description, p.createdAt,
               c.clientId, c.firstName || ' ' || c.lastName AS clientName,
               o.orgName,
               (SELECT COUNT(*) FROM reservation WHERE projectId = p.projectId) AS resv_count,
               (SELECT COUNT(*) FROM deployment WHERE projectId = p.projectId) AS dep_count
        FROM project p
        JOIN client c ON p.clientId = c.clientId
        LEFT JOIN organization o ON c.orgId = o.orgId
        WHERE 1=1
    """
    params = []
    if search:
        sql += " AND (p.projectName LIKE ? OR c.firstName || ' ' || c.lastName LIKE ? OR o.orgName LIKE ?)"
        s = f'%{search}%'
        params.extend([s, s, s])
    sql += " ORDER BY p.createdAt DESC"
    rows = db.execute(sql, params).fetchall()
    return render_template('projects.html', projects=rows, active_page='projects')


@app.route('/project/<int:project_id>')
def project_detail(project_id):
    db = get_db()
    project = db.execute("""
        SELECT p.*, c.firstName || ' ' || c.lastName AS clientName, c.clientId,
               o.orgName, o.orgId
        FROM project p
        JOIN client c ON p.clientId = c.clientId
        LEFT JOIN organization o ON c.orgId = o.orgId
        WHERE p.projectId = ?
    """, (project_id,)).fetchone()
    if not project:
        abort(404)
    reservations = db.execute("""
        SELECT * FROM reservation WHERE projectId = ? ORDER BY startTime DESC
    """, (project_id,)).fetchall()
    deployments = db.execute("""
        SELECT * FROM deployment WHERE projectId = ? ORDER BY startedAt DESC
    """, (project_id,)).fetchall()
    return render_template('project_detail.html',
                           project=project, reservations=reservations, deployments=deployments,
                           active_page='projects')


# ---------- 7. Reservations ----------

@app.route('/reservations')
def reservations():
    db = get_db()
    status_filter = request.args.get('status', 'All')
    priority_filter = request.args.get('priority', 'All')
    search = request.args.get('search', '')
    sort = request.args.get('sort', 'startTime')
    order = request.args.get('order', 'desc').lower()
    if order not in ('asc', 'desc'):
        order = 'desc'
    allowed = {
        'reservationId': 'r.reservationId',
        'startTime': 'r.startTime',
        'endTime': 'r.endTime',
        'status': 'r.status',
        'priority': 'r.priority',
        'clientName': 'clientName',
    }
    sort_col = allowed.get(sort, 'r.startTime')

    sql = f"""
        SELECT r.reservationId, r.startTime, r.endTime, r.status, r.priority, r.depositAmount,
               c.firstName || ' ' || c.lastName AS clientName, c.clientId,
               p.projectId, p.projectName,
               (SELECT COUNT(*) FROM reservation_resource WHERE reservationId = r.reservationId) AS resource_count
        FROM reservation r
        JOIN client c ON r.clientId = c.clientId
        LEFT JOIN project p ON r.projectId = p.projectId
        LEFT JOIN organization o ON c.orgId = o.orgId
        WHERE 1=1
    """
    params = []
    if status_filter != 'All':
        sql += " AND r.status = ?"
        params.append(status_filter)
    if priority_filter != 'All':
        sql += " AND r.priority = ?"
        params.append(priority_filter)
    if search:
        sql += " AND (c.firstName LIKE ? OR c.lastName LIKE ? OR c.firstName || ' ' || c.lastName LIKE ? OR p.projectName LIKE ? OR o.orgName LIKE ?)"
        s = f'%{search}%'
        params.extend([s, s, s, s, s])
    sql += f" ORDER BY {sort_col} {order}"
    rows = db.execute(sql, params).fetchall()

    statuses = db.execute("SELECT DISTINCT status FROM reservation").fetchall()
    priorities = db.execute("SELECT DISTINCT priority FROM reservation").fetchall()
    return render_template('reservations.html',
                           reservations=rows, statuses=statuses, priorities=priorities,
                           active_page='reservations')


@app.route('/reservation/<int:reservation_id>')
def reservation_detail(reservation_id):
    db = get_db()
    resv = db.execute("""
        SELECT r.*, c.firstName || ' ' || c.lastName AS clientName, c.clientId, c.email AS clientEmail,
               p.projectId, p.projectName
        FROM reservation r
        JOIN client c ON r.clientId = c.clientId
        LEFT JOIN project p ON r.projectId = p.projectId
        WHERE r.reservationId = ?
    """, (reservation_id,)).fetchone()
    if not resv:
        abort(404)
    res_resources = db.execute("""
        SELECT rr.*, res.serialNumber, res.status AS resStatus,
               rt.typeName, dc.name AS datacenterName
        FROM reservation_resource rr
        JOIN resource res ON rr.resourceId = res.resourceId
        JOIN resource_type rt ON res.resourceTypeId = rt.resourceTypeId
        JOIN data_center dc ON res.datacenterId = dc.datacenterId
        WHERE rr.reservationId = ?
        ORDER BY rt.typeName, res.serialNumber
    """, (reservation_id,)).fetchall()
    deployments = db.execute("""
        SELECT * FROM deployment WHERE reservationId = ? ORDER BY startedAt DESC
    """, (reservation_id,)).fetchall()
    return render_template('reservation_detail.html',
                           resv=resv, res_resources=res_resources, deployments=deployments,
                           active_page='reservations')


@app.route('/reservation/<int:reservation_id>/edit', methods=['GET', 'POST'])
def reservation_edit(reservation_id):
    db = get_db()
    resv = db.execute("""
        SELECT r.*, c.firstName || ' ' || c.lastName AS clientName, c.clientId
        FROM reservation r
        JOIN client c ON r.clientId = c.clientId
        WHERE r.reservationId = ?
    """, (reservation_id,)).fetchone()
    if not resv:
        abort(404)

    def render_edit(error=None):
        current_resource_ids = set(
            row[0] for row in db.execute(
                "SELECT resourceId FROM reservation_resource WHERE reservationId=?",
                (reservation_id,)
            ).fetchall()
        )
        projects_list = db.execute("""
            SELECT p.projectId, p.projectName, c.firstName || ' ' || c.lastName AS clientName
            FROM project p JOIN client c ON p.clientId = c.clientId
            WHERE p.clientId = ?
            ORDER BY p.projectName
        """, (resv['clientId'],)).fetchall()
        all_resources = db.execute("""
            SELECT res.resourceId, res.serialNumber, res.status,
                   rt.typeName, dc.name AS datacenterName, r.regionName
            FROM resource res
            JOIN resource_type rt ON res.resourceTypeId = rt.resourceTypeId
            JOIN data_center dc ON res.datacenterId = dc.datacenterId
            JOIN availability_zone az ON dc.zoneId = az.zoneId
            JOIN region r ON az.regionId = r.regionId
            WHERE res.status IN ('available', 'in-use')
               OR res.resourceId IN (
                   SELECT resourceId FROM reservation_resource WHERE reservationId = ?
               )
            ORDER BY rt.typeName, res.serialNumber
        """, (reservation_id,)).fetchall()
        statuses = ['pending', 'confirmed', 'completed', 'cancelled']
        return render_template('reservation_edit.html',
                               resv=resv, projects=projects_list,
                               all_resources=all_resources,
                               current_resource_ids=current_resource_ids,
                               statuses=statuses,
                               error=error,
                               active_page='reservations')

    if request.method == 'POST':
        start_time    = normalize_datetime(request.form.get('start_time'))
        end_time      = normalize_datetime(request.form.get('end_time'))
        priority      = request.form.get('priority', 'standard')
        status        = request.form.get('status', 'pending')
        deposit       = request.form.get('deposit_amount') or 0
        project_id    = request.form.get('project_id') or None
        try:
            new_res_ids = set(int(x) for x in request.form.getlist('resource_ids'))
        except ValueError:
            return render_edit('Invalid resource selection.')

        if not start_time or not end_time or end_time <= start_time:
            return render_edit('End time must be after start time.')

        if project_id:
            project_owner = db.execute(
                "SELECT clientId FROM project WHERE projectId = ?",
                (project_id,)
            ).fetchone()
            if not project_owner or project_owner['clientId'] != resv['clientId']:
                return render_edit('Selected project does not belong to this client.')

        if new_res_ids:
            placeholders = ','.join('?' for _ in new_res_ids)
            conflicts = db.execute(f"""
                SELECT DISTINCT res.serialNumber, r.reservationId
                FROM reservation_resource rr
                JOIN reservation r ON rr.reservationId = r.reservationId
                JOIN resource res ON rr.resourceId = res.resourceId
                WHERE rr.resourceId IN ({placeholders})
                  AND r.reservationId != ?
                  AND r.status IN ('pending', 'confirmed')
                  AND r.startTime < ?
                  AND r.endTime > ?
                ORDER BY res.serialNumber
            """, [*new_res_ids, reservation_id, end_time, start_time]).fetchall()
            if conflicts:
                conflict_names = ', '.join(row['serialNumber'] for row in conflicts)
                return render_edit(f'Resource conflict for: {conflict_names}.')

        db.execute("""
            UPDATE reservation
            SET startTime=?, endTime=?, priority=?, status=?, depositAmount=?, projectId=?
            WHERE reservationId=?
        """, (start_time, end_time, priority, status, deposit, project_id, reservation_id))

        old_res_ids = set(
            row[0] for row in db.execute(
                "SELECT resourceId FROM reservation_resource WHERE reservationId=?",
                (reservation_id,)
            ).fetchall()
        )
        now = SYSTEM_DATE.strftime('%Y-%m-%d %H:%M:%S')
        for rid in new_res_ids - old_res_ids:
            db.execute(
                "INSERT INTO reservation_resource (reservationId, resourceId, assignedAt) VALUES (?,?,?)",
                (reservation_id, rid, now)
            )
        for rid in old_res_ids - new_res_ids:
            db.execute(
                "DELETE FROM reservation_resource WHERE reservationId=? AND resourceId=?",
                (reservation_id, rid)
            )
        db.commit()
        return redirect(url_for('reservation_detail', reservation_id=reservation_id))

    return render_edit()


@app.route('/reservations/new', methods=['GET', 'POST'])
def new_reservation():
    db = get_db()

    def render_new(error=None):
        clients_list = db.execute("""
            SELECT c.clientId, c.firstName || ' ' || c.lastName AS name, o.orgName
            FROM client c
            LEFT JOIN organization o ON c.orgId = o.orgId
            ORDER BY c.lastName, c.firstName
        """).fetchall()
        projects_list = db.execute("""
            SELECT p.projectId, p.projectName, c.firstName || ' ' || c.lastName AS clientName
            FROM project p
            JOIN client c ON p.clientId = c.clientId
            ORDER BY p.projectName
        """).fetchall()
        available_resources = db.execute("""
            SELECT res.resourceId, res.serialNumber, res.status,
                   rt.typeName, dc.name AS datacenterName, r.regionName
            FROM resource res
            JOIN resource_type rt ON res.resourceTypeId = rt.resourceTypeId
            JOIN data_center dc ON res.datacenterId = dc.datacenterId
            JOIN availability_zone az ON dc.zoneId = az.zoneId
            JOIN region r ON az.regionId = r.regionId
            WHERE res.status = 'available'
            ORDER BY rt.typeName, res.serialNumber
        """).fetchall()
        return render_template('reservation_new.html',
                               clients=clients_list, projects=projects_list,
                               resources=available_resources,
                               error=error,
                               active_page='reservations')

    if request.method == 'POST':
        client_id = request.form.get('client_id')
        project_id = request.form.get('project_id') or None
        start_time = normalize_datetime(request.form.get('start_time'))
        end_time = normalize_datetime(request.form.get('end_time'))
        priority = request.form.get('priority', 'standard')
        deposit = request.form.get('deposit_amount') or 0
        try:
            resource_ids = [int(x) for x in request.form.getlist('resource_ids')]
        except ValueError:
            return render_new('Invalid resource selection.')
        resource_ids = sorted(set(resource_ids))

        if not start_time or not end_time or end_time <= start_time:
            return render_new('End time must be after start time.')

        client = db.execute("SELECT clientId FROM client WHERE clientId = ?", (client_id,)).fetchone()
        if not client:
            return render_new('Select a valid client.')

        if project_id:
            project_owner = db.execute(
                "SELECT clientId FROM project WHERE projectId = ?",
                (project_id,)
            ).fetchone()
            if not project_owner or project_owner['clientId'] != int(client_id):
                return render_new('Selected project does not belong to this client.')

        if resource_ids:
            placeholders = ','.join('?' for _ in resource_ids)
            valid_resources = db.execute(f"""
                SELECT COUNT(*) FROM resource
                WHERE resourceId IN ({placeholders}) AND status = 'available'
            """, resource_ids).fetchone()[0]
            if valid_resources != len(set(resource_ids)):
                return render_new('Selected resources are no longer available.')

            conflicts = db.execute(f"""
                SELECT DISTINCT res.serialNumber, r.reservationId
                FROM reservation_resource rr
                JOIN reservation r ON rr.reservationId = r.reservationId
                JOIN resource res ON rr.resourceId = res.resourceId
                WHERE rr.resourceId IN ({placeholders})
                  AND r.status IN ('pending', 'confirmed')
                  AND r.startTime < ?
                  AND r.endTime > ?
                ORDER BY res.serialNumber
            """, [*resource_ids, end_time, start_time]).fetchall()
            if conflicts:
                conflict_names = ', '.join(row['serialNumber'] for row in conflicts)
                return render_new(f'Resource conflict for: {conflict_names}.')

        cur = db.cursor()
        cur.execute("""
            INSERT INTO reservation (clientId, projectId, startTime, endTime, status, priority, depositAmount)
            VALUES (?, ?, ?, ?, 'pending', ?, ?)
        """, (client_id, project_id, start_time, end_time, priority, deposit))
        new_id = cur.lastrowid
        now = SYSTEM_DATE.strftime('%Y-%m-%d %H:%M:%S')
        for rid in resource_ids:
            cur.execute("""
                INSERT INTO reservation_resource (reservationId, resourceId, assignedAt)
                VALUES (?, ?, ?)
            """, (new_id, rid, now))
        db.commit()
        return redirect(url_for('reservation_detail', reservation_id=new_id))

    return render_new()


# ---------- 8. Deployments ----------

@app.route('/deployments')
def deployments():
    db = get_db()
    status_filter = request.args.get('status', 'All')
    search = request.args.get('search', '')
    sort = request.args.get('sort', 'startedAt')
    order = request.args.get('order', 'desc').lower()
    if order not in ('asc', 'desc'):
        order = 'desc'
    allowed = {
        'deploymentId': 'd.deploymentId',
        'deploymentName': 'd.deploymentName',
        'status': 'd.status',
        'priority': 'd.priority',
        'startedAt': 'd.startedAt',
        'clientName': 'clientName',
    }
    sort_col = allowed.get(sort, 'd.startedAt')

    sql = f"""
        SELECT d.deploymentId, d.deploymentName, d.status, d.priority,
               d.startedAt, d.stoppedAt, d.autoScale,
               c.firstName || ' ' || c.lastName AS clientName, c.clientId,
               p.projectName, p.projectId,
               (SELECT COUNT(*) FROM deployment_resource WHERE deploymentId = d.deploymentId AND deallocatedAt IS NULL) AS active_resources
        FROM deployment d
        JOIN reservation r ON d.reservationId = r.reservationId
        JOIN client c ON r.clientId = c.clientId
        LEFT JOIN project p ON d.projectId = p.projectId
        LEFT JOIN organization o ON c.orgId = o.orgId
        WHERE 1=1
    """
    params = []
    if status_filter != 'All':
        sql += " AND d.status = ?"
        params.append(status_filter)
    if search:
        sql += " AND (d.deploymentName LIKE ? OR c.firstName LIKE ? OR c.lastName LIKE ? OR c.firstName || ' ' || c.lastName LIKE ? OR o.orgName LIKE ?)"
        s = f'%{search}%'
        params.extend([s, s, s, s, s])
    sql += f" ORDER BY {sort_col} {order}"
    rows = db.execute(sql, params).fetchall()

    statuses = ['active', 'terminated']
    return render_template('deployments.html', deployments=rows, statuses=statuses, active_page='deployments')


@app.route('/deployment/<int:deployment_id>')
def deployment_detail(deployment_id):
    db = get_db()
    dep = db.execute("""
        SELECT d.*, c.firstName || ' ' || c.lastName AS clientName, c.clientId,
               r.reservationId, p.projectId, p.projectName
        FROM deployment d
        JOIN reservation r ON d.reservationId = r.reservationId
        JOIN client c ON r.clientId = c.clientId
        LEFT JOIN project p ON d.projectId = p.projectId
        WHERE d.deploymentId = ?
    """, (deployment_id,)).fetchone()
    if not dep:
        abort(404)
    dep_resources = db.execute("""
        SELECT dr.*, res.resourceId, res.serialNumber, res.status AS resStatus,
               rt.typeName, dc.name AS datacenterName
        FROM deployment_resource dr
        JOIN resource res ON dr.resourceId = res.resourceId
        JOIN resource_type rt ON res.resourceTypeId = rt.resourceTypeId
        JOIN data_center dc ON res.datacenterId = dc.datacenterId
        WHERE dr.deploymentId = ?
        ORDER BY dr.allocatedAt DESC
    """, (deployment_id,)).fetchall()

    # Combined timeline: deployment_event + scaling_event
    events = db.execute("""
        SELECT eventType, timestamp AS ts, notes,
               NULL AS previousScale, NULL AS newScale,
               (SELECT name FROM staff WHERE staffId = de.staffId) AS staffName,
               'event' AS rowKind
        FROM deployment_event de
        WHERE deploymentId = ?
        UNION ALL
        SELECT eventType, triggeredAt AS ts, NULL AS notes,
               previousScale, newScale,
               (SELECT name FROM staff WHERE staffId = se.staffId) AS staffName,
               'scale' AS rowKind
        FROM scaling_event se
        WHERE deploymentId = ?
        ORDER BY ts DESC
    """, (deployment_id, deployment_id)).fetchall()

    charges = db.execute("""
        SELECT ch.*, st.serviceName, st.unitOfMeasure
        FROM charge ch
        JOIN service_type st ON ch.serviceTypeId = st.serviceTypeId
        WHERE ch.deploymentId = ?
        ORDER BY ch.chargedAt DESC
    """, (deployment_id,)).fetchall()
    total_charges = sum(c['amount'] for c in charges)
    return render_template('deployment_detail.html',
                           dep=dep, dep_resources=dep_resources, events=events,
                           charges=charges, total_charges=total_charges,
                           active_page='deployments')


@app.route('/deployment/<int:deployment_id>/stop', methods=['POST'])
def deployment_stop(deployment_id):
    db = get_db()
    now = SYSTEM_DATE.strftime('%Y-%m-%d %H:%M:%S')
    db.execute("UPDATE deployment SET status = 'terminated', stoppedAt = ? WHERE deploymentId = ?", (now, deployment_id))
    db.execute("""
        INSERT INTO deployment_event (deploymentId, eventType, timestamp, notes)
        VALUES (?, 'stop', ?, 'Stopped via internal ops console')
    """, (deployment_id, now))
    db.commit()
    return redirect(url_for('deployment_detail', deployment_id=deployment_id))


@app.route('/deployment/<int:deployment_id>/start', methods=['POST'])
def deployment_start(deployment_id):
    db = get_db()
    now = SYSTEM_DATE.strftime('%Y-%m-%d %H:%M:%S')
    db.execute("UPDATE deployment SET status = 'active', stoppedAt = NULL WHERE deploymentId = ?", (deployment_id,))
    db.execute("""
        INSERT INTO deployment_event (deploymentId, eventType, timestamp, notes)
        VALUES (?, 'start', ?, 'Started via internal ops console')
    """, (deployment_id, now))
    db.commit()
    return redirect(url_for('deployment_detail', deployment_id=deployment_id))


# ---------- 9. Billing ----------

@app.route('/billing')
def billing():
    db = get_db()
    accounts = db.execute("""
        SELECT ba.*,
               COALESCE(o.orgName, c.firstName || ' ' || c.lastName) AS ownerName,
               CASE WHEN ba.orgId IS NOT NULL THEN 'Organization' ELSE 'Client' END AS ownerType,
               COALESCE((SELECT SUM(amount) FROM charge WHERE billingAccountId = ba.billingAccountId), 0) AS total_charges,
               COALESCE((SELECT SUM(totalAmount) FROM invoice WHERE billingAccountId = ba.billingAccountId AND status = 'pending'), 0) AS outstanding,
               (SELECT COUNT(*) FROM invoice WHERE billingAccountId = ba.billingAccountId) AS invoice_count
        FROM billing_account ba
        LEFT JOIN organization o ON ba.orgId = o.orgId
        LEFT JOIN client c ON ba.clientId = c.clientId
        ORDER BY ba.accountName
    """).fetchall()
    return render_template('billing.html', accounts=accounts, active_page='billing')


@app.route('/billing/account/<int:account_id>')
def billing_account_detail(account_id):
    db = get_db()
    account = db.execute("""
        SELECT ba.*,
               COALESCE(o.orgName, c.firstName || ' ' || c.lastName) AS ownerName,
               o.orgId, c.clientId
        FROM billing_account ba
        LEFT JOIN organization o ON ba.orgId = o.orgId
        LEFT JOIN client c ON ba.clientId = c.clientId
        WHERE ba.billingAccountId = ?
    """, (account_id,)).fetchone()
    if not account:
        abort(404)
    invoices = db.execute("""
        SELECT * FROM invoice WHERE billingAccountId = ? ORDER BY periodStart DESC
    """, (account_id,)).fetchall()
    charges = db.execute("""
        SELECT ch.*, st.serviceName, d.deploymentName,
               (SELECT SUM(amount) FROM adjustment WHERE chargeId = ch.chargeId) AS adjustment_total
        FROM charge ch
        JOIN service_type st ON ch.serviceTypeId = st.serviceTypeId
        JOIN deployment d ON ch.deploymentId = d.deploymentId
        WHERE ch.billingAccountId = ?
        ORDER BY ch.chargedAt DESC
    """, (account_id,)).fetchall()
    cost_centers = db.execute("""
        SELECT cc.*,
               COALESCE((SELECT SUM(ca.amount)
                          FROM charge_allocation ca WHERE ca.costCenterId = cc.costCenterId), 0) AS spend
        FROM cost_center cc
        WHERE cc.billingAccountId = ?
    """, (account_id,)).fetchall()
    total_charges = sum(c['amount'] for c in charges)
    total_outstanding = sum(i['totalAmount'] for i in invoices if i['status'] == 'pending')
    return render_template('billing_account_detail.html',
                           account=account, invoices=invoices, charges=charges,
                           cost_centers=cost_centers, total_charges=total_charges,
                           total_outstanding=total_outstanding,
                           active_page='billing')


@app.route('/invoices')
def invoices():
    db = get_db()
    status_filter = request.args.get('status', 'All')
    sort = request.args.get('sort', 'periodStart')
    order = request.args.get('order', 'desc').lower()
    if order not in ('asc', 'desc'):
        order = 'desc'
    allowed = {
        'invoiceId': 'i.invoiceId',
        'periodStart': 'i.periodStart',
        'totalAmount': 'i.totalAmount',
        'status': 'i.status',
        'dueAt': 'i.dueAt',
        'accountName': 'ba.accountName',
    }
    sort_col = allowed.get(sort, 'i.periodStart')

    sql = f"""
        SELECT i.*, ba.accountName,
               COALESCE(o.orgName, c.firstName || ' ' || c.lastName) AS ownerName
        FROM invoice i
        JOIN billing_account ba ON i.billingAccountId = ba.billingAccountId
        LEFT JOIN organization o ON ba.orgId = o.orgId
        LEFT JOIN client c ON ba.clientId = c.clientId
        WHERE 1=1
    """
    params = []
    if status_filter != 'All':
        sql += " AND i.status = ?"
        params.append(status_filter)
    sql += f" ORDER BY {sort_col} {order}"
    rows = db.execute(sql, params).fetchall()
    return render_template('invoices.html', invoices=rows, active_page='invoices')


@app.route('/invoice/<int:invoice_id>')
def invoice_detail(invoice_id):
    db = get_db()
    invoice = db.execute("""
        SELECT i.*, ba.accountName, ba.billingAccountId,
               COALESCE(o.orgName, c.firstName || ' ' || c.lastName) AS ownerName
        FROM invoice i
        JOIN billing_account ba ON i.billingAccountId = ba.billingAccountId
        LEFT JOIN organization o ON ba.orgId = o.orgId
        LEFT JOIN client c ON ba.clientId = c.clientId
        WHERE i.invoiceId = ?
    """, (invoice_id,)).fetchone()
    if not invoice:
        abort(404)
    line_items = db.execute("""
        SELECT ch.*, st.serviceName, st.unitOfMeasure, d.deploymentName, d.deploymentId
        FROM charge ch
        JOIN service_type st ON ch.serviceTypeId = st.serviceTypeId
        JOIN deployment d ON ch.deploymentId = d.deploymentId
        WHERE ch.invoiceId = ?
        ORDER BY ch.chargedAt
    """, (invoice_id,)).fetchall()
    allocations = db.execute("""
        SELECT ca.*, cc.centerName, ch.chargedAt
        FROM charge_allocation ca
        JOIN cost_center cc ON ca.costCenterId = cc.costCenterId
        JOIN charge ch ON ca.chargeId = ch.chargeId
        WHERE ch.invoiceId = ?
    """, (invoice_id,)).fetchall()
    return render_template('invoice_detail.html',
                           invoice=invoice, line_items=line_items, allocations=allocations,
                           active_page='invoices')


@app.route('/cost-centers')
def cost_centers():
    db = get_db()
    rows = db.execute("""
        SELECT cc.*, ba.accountName,
               COALESCE(o.orgName, c.firstName || ' ' || c.lastName) AS ownerName,
               COALESCE((SELECT SUM(amount) FROM charge_allocation WHERE costCenterId = cc.costCenterId), 0) AS spend
        FROM cost_center cc
        JOIN billing_account ba ON cc.billingAccountId = ba.billingAccountId
        LEFT JOIN organization o ON ba.orgId = o.orgId
        LEFT JOIN client c ON ba.clientId = c.clientId
        ORDER BY ba.accountName, cc.centerName
    """).fetchall()
    return render_template('cost_centers.html', centers=rows, active_page='cost_centers')


# ---------- 10. Operations ----------

@app.route('/maintenance')
def maintenance():
    db = get_db()
    sort = request.args.get('sort', 'scheduledStart')
    order = request.args.get('order', 'desc').lower()
    if order not in ('asc', 'desc'):
        order = 'desc'
    allowed = {
        'maintenanceId': 'm.maintenanceId',
        'maintenanceType': 'm.maintenanceType',
        'scheduledStart': 'm.scheduledStart',
        'staffName': 'staffName',
        'serialNumber': 'r.serialNumber',
    }
    sort_col = allowed.get(sort, 'm.scheduledStart')
    rows = db.execute(f"""
        SELECT m.*, r.serialNumber, r.resourceId, s.name AS staffName, s.staffId,
               rt.typeName, dc.name AS datacenterName
        FROM maintenanceLog m
        JOIN resource r ON m.resourceId = r.resourceId
        JOIN resource_type rt ON r.resourceTypeId = rt.resourceTypeId
        JOIN data_center dc ON r.datacenterId = dc.datacenterId
        JOIN staff s ON m.staffId = s.staffId
        ORDER BY {sort_col} {order}
    """).fetchall()
    return render_template('maintenance.html', maintenance=rows, active_page='maintenance')


@app.route('/access-log')
def access_log():
    db = get_db()
    action_filter = request.args.get('action', 'All')
    search = request.args.get('search', '')
    sql = """
        SELECT al.*, c.firstName || ' ' || c.lastName AS clientName,
               r.serialNumber, d.deploymentName
        FROM accessLog al
        JOIN client c ON al.clientId = c.clientId
        JOIN resource r ON al.resourceId = r.resourceId
        LEFT JOIN deployment d ON al.deploymentId = d.deploymentId
        WHERE 1=1
    """
    params = []
    if action_filter != 'All':
        sql += " AND al.action = ?"
        params.append(action_filter)
    if search:
        sql += " AND (c.firstName LIKE ? OR c.lastName LIKE ? OR r.serialNumber LIKE ? OR al.ipAddress LIKE ?)"
        s = f'%{search}%'
        params.extend([s, s, s, s])
    sql += " ORDER BY al.loggedAt DESC LIMIT 200"
    rows = db.execute(sql, params).fetchall()
    actions = db.execute("SELECT DISTINCT action FROM accessLog").fetchall()
    return render_template('access_log.html', logs=rows, actions=actions, active_page='access_log')


@app.route('/credentials')
def credentials():
    db = get_db()
    today_str = SYSTEM_DATE.strftime('%Y-%m-%d')
    soon_str = (SYSTEM_DATE + timedelta(days=30)).strftime('%Y-%m-%d')
    rows = db.execute("""
        SELECT cr.*, c.firstName || ' ' || c.lastName AS clientName, c.email,
               CASE
                   WHEN cr.isActive = 0 THEN 'inactive'
                   WHEN cr.expiresAt IS NOT NULL AND cr.expiresAt < ? THEN 'expired'
                   WHEN cr.expiresAt IS NOT NULL AND cr.expiresAt < ? THEN 'expiring-soon'
                   ELSE 'active'
               END AS effective_status
        FROM credential cr
        JOIN client c ON cr.clientId = c.clientId
        ORDER BY cr.createdAt DESC
    """, (today_str, soon_str)).fetchall()
    return render_template('credentials.html', credentials=rows, active_page='credentials')


@app.route('/staff')
def staff():
    db = get_db()
    active_filter = request.args.get('active', 'All')
    sql = """
        SELECT s.*,
               (SELECT COUNT(*) FROM maintenanceLog WHERE staffId = s.staffId) AS maint_count,
               (SELECT COUNT(*) FROM adjustment WHERE staffId = s.staffId) AS adj_count,
               (SELECT COUNT(*) FROM scaling_event WHERE staffId = s.staffId) AS scale_count
        FROM staff s
        WHERE 1=1
    """
    params = []
    if active_filter == 'Active':
        sql += " AND s.isActive = 1"
    elif active_filter == 'Inactive':
        sql += " AND s.isActive = 0"
    sql += " ORDER BY s.name"
    rows = db.execute(sql, params).fetchall()
    return render_template('staff.html', staff=rows, active_page='staff')


# ---------- 11. Capacity ----------

@app.route('/capacity')
def capacity():
    db = get_db()
    from_date = request.args.get('from_date', SYSTEM_DATE.strftime('%Y-%m-%d'))
    to_date   = request.args.get('to_date',   (SYSTEM_DATE + timedelta(days=30)).strftime('%Y-%m-%d'))
    type_filter   = request.args.get('type', 'All')
    region_filter = request.args.get('region', 'All')

    # Base filters
    extra_sql, params = '', []
    if type_filter != 'All':
        extra_sql += " AND rt.typeName = ?"
        params.append(type_filter)
    if region_filter != 'All':
        extra_sql += " AND reg.regionName = ?"
        params.append(region_filter)

    # Pick one matching reservation per resource so KPI totals stay resource-based.
    rows = db.execute(f"""
        SELECT res.resourceId, res.serialNumber, res.status,
               rt.typeName, dc.name AS datacenterName, reg.regionName,
               (
                   SELECT resv.reservationId
                   FROM reservation_resource rr
                   JOIN reservation resv ON rr.reservationId = resv.reservationId
                   WHERE rr.resourceId = res.resourceId
                     AND resv.status IN ('confirmed','pending')
                     AND resv.startTime < ? AND resv.endTime > ?
                   ORDER BY resv.startTime
                   LIMIT 1
               ) AS reservationId,
               (
                   SELECT resv.startTime
                   FROM reservation_resource rr
                   JOIN reservation resv ON rr.reservationId = resv.reservationId
                   WHERE rr.resourceId = res.resourceId
                     AND resv.status IN ('confirmed','pending')
                     AND resv.startTime < ? AND resv.endTime > ?
                   ORDER BY resv.startTime
                   LIMIT 1
               ) AS startTime,
               (
                   SELECT resv.endTime
                   FROM reservation_resource rr
                   JOIN reservation resv ON rr.reservationId = resv.reservationId
                   WHERE rr.resourceId = res.resourceId
                     AND resv.status IN ('confirmed','pending')
                     AND resv.startTime < ? AND resv.endTime > ?
                   ORDER BY resv.startTime
                   LIMIT 1
               ) AS endTime,
               (
                   SELECT c.firstName || ' ' || c.lastName
                   FROM reservation_resource rr
                   JOIN reservation resv ON rr.reservationId = resv.reservationId
                   JOIN client c ON resv.clientId = c.clientId
                   WHERE rr.resourceId = res.resourceId
                     AND resv.status IN ('confirmed','pending')
                     AND resv.startTime < ? AND resv.endTime > ?
                   ORDER BY resv.startTime
                   LIMIT 1
               ) AS clientName,
               (
                   SELECT c.clientId
                   FROM reservation_resource rr
                   JOIN reservation resv ON rr.reservationId = resv.reservationId
                   JOIN client c ON resv.clientId = c.clientId
                   WHERE rr.resourceId = res.resourceId
                     AND resv.status IN ('confirmed','pending')
                     AND resv.startTime < ? AND resv.endTime > ?
                   ORDER BY resv.startTime
                   LIMIT 1
               ) AS clientId
        FROM resource res
        JOIN resource_type rt  ON res.resourceTypeId = rt.resourceTypeId
        JOIN data_center dc    ON res.datacenterId   = dc.datacenterId
        JOIN availability_zone az ON dc.zoneId       = az.zoneId
        JOIN region reg        ON az.regionId        = reg.regionId
        WHERE 1=1 {extra_sql}
        ORDER BY
            CASE
                WHEN reservationId IS NOT NULL THEN 1
                WHEN res.status = 'maintenance' THEN 3
                ELSE 2
            END,
            rt.typeName,
            res.serialNumber
    """, [to_date, from_date] * 5 + params).fetchall()

    # KPIs
    total      = len(rows)
    booked     = sum(1 for r in rows if r['reservationId'] is not None)
    in_maint   = sum(1 for r in rows if r['status'] == 'maintenance')
    available  = total - booked - in_maint

    # Summary by type
    type_summary = db.execute(f"""
        SELECT rt.typeName,
               COUNT(DISTINCT res.resourceId) AS total,
               COUNT(DISTINCT CASE WHEN resv.reservationId IS NOT NULL THEN res.resourceId END) AS booked,
               COUNT(DISTINCT CASE WHEN res.status = 'maintenance' THEN res.resourceId END) AS in_maint
        FROM resource res
        JOIN resource_type rt ON res.resourceTypeId = rt.resourceTypeId
        JOIN data_center dc   ON res.datacenterId   = dc.datacenterId
        JOIN availability_zone az ON dc.zoneId      = az.zoneId
        JOIN region reg       ON az.regionId        = reg.regionId
        LEFT JOIN reservation_resource rr ON res.resourceId = rr.resourceId
        LEFT JOIN reservation resv ON rr.reservationId = resv.reservationId
            AND resv.status IN ('confirmed','pending')
            AND resv.startTime < ? AND resv.endTime > ?
        WHERE 1=1 {extra_sql}
        GROUP BY rt.typeName
        ORDER BY rt.typeName
    """, [to_date, from_date] + params).fetchall()

    types   = db.execute("SELECT typeName FROM resource_type ORDER BY typeName").fetchall()
    regions = db.execute("SELECT regionName FROM region ORDER BY regionName").fetchall()

    return render_template('capacity.html',
                           rows=rows, type_summary=type_summary,
                           types=types, regions=regions,
                           from_date=from_date, to_date=to_date,
                           type_filter=type_filter, region_filter=region_filter,
                           kpi={'total': total, 'available': available,
                                'booked': booked, 'in_maint': in_maint},
                           active_page='capacity')


# ---------- 12. Reports ----------

@app.route('/reports')
def reports():
    db = get_db()

    # 1. Top 10 clients by spend
    top_clients = db.execute("""
        SELECT c.clientId, c.firstName || ' ' || c.lastName AS clientName,
               o.orgName,
               COUNT(DISTINCT d.deploymentId) AS deploys,
               SUM(ch.amount) AS total_spend
        FROM client c
        JOIN reservation r ON c.clientId = r.clientId
        JOIN deployment d ON r.reservationId = d.reservationId
        JOIN charge ch ON d.deploymentId = ch.deploymentId
        LEFT JOIN organization o ON c.orgId = o.orgId
        GROUP BY c.clientId
        ORDER BY total_spend DESC
        LIMIT 10
    """).fetchall()

    # 2. Resource utilization by type
    util_by_type = db.execute("""
        SELECT rt.typeName,
               COUNT(res.resourceId) AS total,
               SUM(CASE WHEN res.status = 'in-use' THEN 1 ELSE 0 END) AS in_use
        FROM resource_type rt
        LEFT JOIN resource res ON rt.resourceTypeId = res.resourceTypeId
        GROUP BY rt.typeName
        ORDER BY rt.typeName
    """).fetchall()

    # 3. Monthly revenue trend
    monthly = db.execute("""
        SELECT strftime('%Y-%m', chargedAt) AS month,
               SUM(amount) AS total_rev
        FROM charge
        GROUP BY month
        ORDER BY month
    """).fetchall()

    # 4. Revenue by service type
    by_service = db.execute("""
        SELECT st.serviceName, SUM(ch.amount) AS total
        FROM charge ch
        JOIN service_type st ON ch.serviceTypeId = st.serviceTypeId
        GROUP BY st.serviceName
        ORDER BY total DESC
    """).fetchall()

    # 5. Revenue by region
    by_region = db.execute("""
        SELECT r.regionName, SUM(ch.amount) AS total
        FROM charge ch
        JOIN deployment d ON ch.deploymentId = d.deploymentId
        JOIN deployment_resource dr ON d.deploymentId = dr.deploymentId
        JOIN resource res ON dr.resourceId = res.resourceId
        JOIN data_center dc ON res.datacenterId = dc.datacenterId
        JOIN availability_zone az ON dc.zoneId = az.zoneId
        JOIN region r ON az.regionId = r.regionId
        GROUP BY r.regionName
        ORDER BY total DESC
    """).fetchall()

    # 6. Avg deployment duration by resource type
    avg_duration = db.execute("""
        SELECT rt.typeName,
               COUNT(DISTINCT d.deploymentId) AS deploys,
               ROUND(AVG(
                 (julianday(COALESCE(d.stoppedAt, ?)) - julianday(d.startedAt)) * 24
               ), 1) AS avg_hours
        FROM deployment d
        JOIN deployment_resource dr ON d.deploymentId = dr.deploymentId
        JOIN resource res ON dr.resourceId = res.resourceId
        JOIN resource_type rt ON res.resourceTypeId = rt.resourceTypeId
        GROUP BY rt.typeName
        ORDER BY avg_hours DESC
    """, (SYSTEM_DATE.strftime('%Y-%m-%d'),)).fetchall()

    # 7. Credits vs surcharges
    adjustments = db.execute("""
        SELECT strftime('%Y-%m', createdAt) AS month,
               adjustmentType,
               SUM(amount) AS total
        FROM adjustment
        GROUP BY month, adjustmentType
        ORDER BY month, adjustmentType
    """).fetchall()

    # 8. Outstanding invoices
    outstanding_invoices = db.execute("""
        SELECT i.*, ba.accountName,
               COALESCE(o.orgName, c.firstName || ' ' || c.lastName) AS ownerName
        FROM invoice i
        JOIN billing_account ba ON i.billingAccountId = ba.billingAccountId
        LEFT JOIN organization o ON ba.orgId = o.orgId
        LEFT JOIN client c ON ba.clientId = c.clientId
        WHERE i.status = 'pending'
        ORDER BY i.dueAt
    """).fetchall()

    # Chart datasets
    c1_labels = [row['month'] for row in monthly]
    c1_data = [row['total_rev'] for row in monthly]

    c2_labels = [row['typeName'] for row in util_by_type]
    c2_data = [round((row['in_use'] / row['total'] * 100), 1) if row['total'] else 0
               for row in util_by_type]

    c3_labels = [row['serviceName'] for row in by_service]
    c3_data = [row['total'] for row in by_service]

    c4_labels = [row['regionName'] for row in by_region]
    c4_data = [row['total'] for row in by_region]

    trend_direction = 'flat'
    if len(monthly) >= 2:
        last = monthly[-1]['total_rev'] or 0
        prev = monthly[-2]['total_rev'] or 0
        trend_direction = 'up' if last >= prev else 'down'

    return render_template('reports.html',
                           top_clients=top_clients,
                           util_by_type=util_by_type,
                           monthly=monthly,
                           by_service=by_service,
                           by_region=by_region,
                           avg_duration=avg_duration,
                           adjustments=adjustments,
                           outstanding_invoices=outstanding_invoices,
                           c1_labels=c1_labels, c1_data=c1_data,
                           c2_labels=c2_labels, c2_data=c2_data,
                           c3_labels=c3_labels, c3_data=c3_data,
                           c4_labels=c4_labels, c4_data=c4_data,
                           trend_direction=trend_direction,
                           active_page='reports')


# ---------- 12. Search ----------

@app.route('/search')
def search():
    db = get_db()
    q = request.args.get('q', '').strip()
    resources_hits, clients_hits, orgs_hits, deployments_hits = [], [], [], []
    if q:
        s = f'%{q}%'
        resources_hits = db.execute("""
            SELECT res.resourceId, res.serialNumber, res.status,
                   rt.typeName, dc.name AS datacenterName
            FROM resource res
            JOIN resource_type rt ON res.resourceTypeId = rt.resourceTypeId
            JOIN data_center dc ON res.datacenterId = dc.datacenterId
            WHERE res.serialNumber LIKE ? OR rt.typeName LIKE ?
            LIMIT 25
        """, (s, s)).fetchall()
        clients_hits = db.execute("""
            SELECT c.clientId, c.firstName, c.lastName, c.email, c.role,
                   o.orgName
            FROM client c
            LEFT JOIN organization o ON c.orgId = o.orgId
            WHERE c.firstName LIKE ? OR c.lastName LIKE ? OR c.email LIKE ?
            LIMIT 25
        """, (s, s, s)).fetchall()
        orgs_hits = db.execute("""
            SELECT * FROM organization
            WHERE orgName LIKE ? OR industry LIKE ? OR contactEmail LIKE ?
            LIMIT 25
        """, (s, s, s)).fetchall()
        deployments_hits = db.execute("""
            SELECT d.deploymentId, d.deploymentName, d.status, d.startedAt,
                   c.firstName || ' ' || c.lastName AS clientName
            FROM deployment d
            JOIN reservation r ON d.reservationId = r.reservationId
            JOIN client c ON r.clientId = c.clientId
            WHERE d.deploymentName LIKE ?
            LIMIT 25
        """, (s,)).fetchall()
    return render_template('search.html', q=q,
                           resources=resources_hits,
                           clients=clients_hits,
                           orgs=orgs_hits,
                           deployments=deployments_hits,
                           active_page='search')


if __name__ == '__main__':
    if not os.path.exists(DATABASE):
        init_db()
    app.run(debug=True, port=5000)
