import sqlite3
import os
from flask import Flask, render_template, request, redirect, url_for, g
from datetime import date, timedelta, datetime

app = Flask(__name__)
DATABASE = os.path.join(app.root_path, 'cloudnine.db')
SYSTEM_DATE = date(2026, 3, 31)


def get_db():
    db = getattr(g, '_database', None)
    if db is None:
        db = g._database = sqlite3.connect(DATABASE)
        db.row_factory = sqlite3.Row
    return db


@app.teardown_appcontext
def close_connection(exception):
    db = getattr(g, '_database', None)
    if db is not None:
        db.close()


@app.route('/')
def dashboard():
    db = get_db()
    month_str = SYSTEM_DATE.strftime('%Y-%m')

    active_count = db.execute("SELECT COUNT(*) FROM deployment WHERE status = 'active'").fetchone()[0]
    total_dep = db.execute("SELECT COUNT(*) FROM deployment").fetchone()[0]
    active_rate = round((active_count / total_dep * 100), 1) if total_dep > 0 else 0

    new_reservations = db.execute(
        "SELECT COUNT(*) FROM reservation WHERE strftime('%Y-%m', startTime) = ?", (month_str,)
    ).fetchone()[0]

    terminations = db.execute(
        "SELECT COUNT(*) FROM deployment WHERE strftime('%Y-%m', stoppedAt) = ?", (month_str,)
    ).fetchone()[0]

    revenue = db.execute(
        "SELECT SUM(amount) FROM charge WHERE strftime('%Y-%m', chargedAt) = ? AND isProvisional = 0",
        (month_str,)
    ).fetchone()[0]
    revenue = round(revenue, 2) if revenue else 0

    arrivals_data = db.execute("""
        SELECT r.reservationId as resvId,
               cl.firstName || ' ' || cl.lastName as guestName,
               r.status,
               COALESCE(res.serialNumber, 'TBD') as roomNumber
        FROM reservation r
        JOIN client cl ON r.clientId = cl.clientId
        LEFT JOIN reservation_resource rr ON r.reservationId = rr.reservationId
        LEFT JOIN resource res ON rr.resourceId = res.resourceId
        WHERE r.status IN ('confirmed', 'pending')
        GROUP BY r.reservationId
        ORDER BY r.startTime DESC
        LIMIT 5
    """).fetchall()

    kpi_data = {
        'occupancy': active_rate,
        'arrivals': new_reservations,
        'departures': terminations,
        'revenue': revenue
    }

    return render_template('dashboard.html', kpi=kpi_data, arrivals=arrivals_data, active_page='dashboard')


@app.route('/rooms')
def rooms():
    db = get_db()
    status_filter = request.args.get('status', 'All')
    search_query = request.args.get('search', '')

    sql = """
        SELECT res.resourceId as roomId, res.serialNumber as roomNumber,
               res.status as currentStatus, res.currentConfig,
               rt.typeName as funcName, rt.category,
               rt.baseHourlyRate as baseRate, rt.performanceTier,
               dc.name as wingName, az.zoneName as floorNo,
               reg.regionName
        FROM resource res
        JOIN resource_type rt ON res.resourceTypeId = rt.resourceTypeId
        JOIN data_center dc ON res.datacenterId = dc.datacenterId
        JOIN availability_zone az ON dc.zoneId = az.zoneId
        JOIN region reg ON az.regionId = reg.regionId
        WHERE 1=1
    """
    params = []
    status_map = {'Clean': 'available', 'Dirty': 'maintenance', 'Occupied': 'in-use'}
    if status_filter != 'All':
        sql += " AND res.status = ?"
        params.append(status_map.get(status_filter, status_filter))
    if search_query:
        sql += " AND (res.serialNumber LIKE ? OR dc.name LIKE ? OR az.zoneName LIKE ?)"
        params.extend([f'%{search_query}%'] * 3)

    rooms_data = db.execute(sql, params).fetchall()
    return render_template('rooms.html', rooms=rooms_data, active_page='rooms')


@app.route('/room/<int:room_id>')
def room_detail(room_id):
    db = get_db()

    room = db.execute("""
        SELECT res.resourceId, res.serialNumber as roomNumber, res.status as currentStatus,
               res.currentConfig, res.commissionedAt,
               rt.typeName as funcName, rt.category as functionCode,
               rt.baseHourlyRate as baseRate, rt.performanceTier, rt.maxCapacity,
               dc.name as wingName, dc.city, dc.country,
               az.zoneName as floorNo, reg.regionName as buildingName,
               0 as isSmokingRoom
        FROM resource res
        JOIN resource_type rt ON res.resourceTypeId = rt.resourceTypeId
        JOIN data_center dc ON res.datacenterId = dc.datacenterId
        JOIN availability_zone az ON dc.zoneId = az.zoneId
        JOIN region reg ON az.regionId = reg.regionId
        WHERE res.resourceId = ?
    """, (room_id,)).fetchone()

    components = db.execute("""
        SELECT componentType as name, specs as capacity, status, 1 as count
        FROM resource_component
        WHERE parentResourceId = ?
        ORDER BY componentId
    """, (room_id,)).fetchall()

    maintenance = db.execute("""
        SELECT ml.maintenanceId as ticketId,
               ml.maintenanceType || COALESCE(' — ' || ml.notes, '') as issueDescription,
               CASE WHEN ml.actualEnd IS NOT NULL THEN 'Resolved' ELSE 'Pending' END as status,
               ml.scheduledStart as dateCreated, ml.actualEnd as dateResolved
        FROM maintenanceLog ml
        WHERE ml.resourceId = ?
        ORDER BY ml.scheduledStart DESC
    """, (room_id,)).fetchall()

    history = db.execute("""
        SELECT dr.allocatedAt as checkInTime, dr.deallocatedAt as checkOutTime,
               cl.firstName || ' ' || cl.lastName as guestName
        FROM deployment_resource dr
        JOIN deployment d ON dr.deploymentId = d.deploymentId
        JOIN reservation r ON d.reservationId = r.reservationId
        JOIN client cl ON r.clientId = cl.clientId
        WHERE dr.resourceId = ?
        ORDER BY dr.allocatedAt DESC
    """, (room_id,)).fetchall()

    adjacencies = db.execute("""
        SELECT res2.resourceId as roomId, res2.serialNumber as roomNumber,
               rt2.typeName as connectionType
        FROM resource res1
        JOIN resource res2 ON res1.datacenterId = res2.datacenterId
            AND res2.resourceId != res1.resourceId
        JOIN resource_type rt2 ON res2.resourceTypeId = rt2.resourceTypeId
        WHERE res1.resourceId = ?
        LIMIT 5
    """, (room_id,)).fetchall()

    return render_template('room_detail.html',
                           room=room, beds=components, fixtures=[],
                           adjacencies=adjacencies, maintenance=maintenance, history=history,
                           active_page='rooms')


@app.route('/reservations')
def reservations():
    db = get_db()
    search_query = request.args.get('search', '')
    sort = request.args.get('sort', 'startDate')
    direction = request.args.get('direction', request.args.get('order', 'desc')).lower()

    allowed_sort_cols = {
        'resvId': 'r.reservationId',
        'startDate': 'r.startTime',
        'endDate': 'r.endTime',
        'status': 'r.status',
        'displayName': 'displayName'
    }
    sort_col = allowed_sort_cols.get(sort, 'r.startTime')
    direction = 'ASC' if direction == 'asc' else 'DESC'

    sql = f"""
        SELECT r.reservationId as resvId, r.startTime as startDate, r.endTime as endDate,
               r.status, r.priority,
               cl.firstName || ' ' || cl.lastName as displayName,
               CASE WHEN cl.orgId IS NOT NULL THEN 'Org' ELSE 'Individual' END as partyType
        FROM reservation r
        JOIN client cl ON r.clientId = cl.clientId
        WHERE 1=1
    """
    params = []
    if search_query:
        sql += """
            AND (cl.firstName LIKE ? OR cl.lastName LIKE ?
                OR (cl.firstName || ' ' || cl.lastName) LIKE ?
                OR EXISTS (
                    SELECT 1 FROM organization o
                    WHERE o.orgId = cl.orgId AND o.orgName LIKE ?))
        """
        s = f'%{search_query}%'
        params.extend([s, s, s, s])
    sql += f" ORDER BY {sort_col} {direction}"

    reservations_list = db.execute(sql, params).fetchall()
    return render_template('reservations.html', reservations=reservations_list, active_page='reservations')


@app.route('/reservations/new', methods=['GET', 'POST'])
def new_reservation():
    db = get_db()
    if request.method == 'POST':
        guest_mode = request.form.get('guest_mode')
        client_id = None
        if guest_mode == 'new':
            first_name = request.form.get('first_name')
            last_name = request.form.get('last_name')
            email = request.form.get('email')
            cursor = db.cursor()
            cursor.execute(
                "INSERT INTO client (clientType, firstName, lastName, email, createdAt) VALUES (?, ?, ?, ?, ?)",
                ('individual', first_name, last_name, email, datetime.now().isoformat())
            )
            client_id = cursor.lastrowid
            db.commit()
        else:
            client_id = request.form.get('party_id')
        start_date = request.form.get('start_date')
        end_date = request.form.get('end_date')
        db.execute(
            "INSERT INTO reservation (clientId, startTime, endTime, status) VALUES (?, ?, ?, 'pending')",
            (client_id, start_date, end_date)
        )
        db.commit()
        return redirect(url_for('reservations'))

    parties = db.execute("""
        SELECT clientId as partyId, firstName || ' ' || lastName as name
        FROM client ORDER BY firstName
    """).fetchall()
    return render_template('reservation_new.html', parties=parties, active_page='reservations')


@app.route('/checkin/<int:resv_id>')
def checkin(resv_id):
    db = get_db()
    resv = db.execute("""
        SELECT r.reservationId as resvId, r.startTime as startDate, r.endTime as endDate,
               cl.firstName || ' ' || cl.lastName as guestName
        FROM reservation r
        JOIN client cl ON r.clientId = cl.clientId
        WHERE r.reservationId = ?
    """, (resv_id,)).fetchone()
    available_rooms = db.execute("""
        SELECT res.resourceId as roomId, res.serialNumber as roomNumber,
               rt.typeName as funcName, res.status as currentStatus,
               rt.baseHourlyRate as baseRate
        FROM resource res
        JOIN resource_type rt ON res.resourceTypeId = rt.resourceTypeId
        WHERE res.status = 'available'
    """).fetchall()
    return render_template('checkin.html', resv=resv, rooms=available_rooms, active_page='reservations')


@app.route('/parties')
def parties():
    db = get_db()
    search_query = request.args.get('search', '')
    sort_col = request.args.get('sort', 'partyId')
    order = request.args.get('order', 'asc').lower()

    allowed_sort_cols = {
        'partyId': 'cl.clientId',
        'displayName': 'displayName',
        'type': 'cl.clientType',
        'email': 'cl.email',
        'phone': 'cl.clientId'
    }
    sort_sql = allowed_sort_cols.get(sort_col, 'cl.clientId')
    if order not in ['asc', 'desc']:
        order = 'asc'

    sql = f"""
        SELECT cl.clientId as partyId, cl.email,
               cl.clientType as type,
               cl.firstName || ' ' || cl.lastName AS displayName,
               COALESCE(o.orgName, 'Independent') as phone
        FROM client cl
        LEFT JOIN organization o ON cl.orgId = o.orgId
        WHERE 1=1
    """
    params = []
    if search_query:
        sql += """
            AND (cl.firstName LIKE ? OR cl.lastName LIKE ?
                OR (cl.firstName || ' ' || cl.lastName) LIKE ? OR o.orgName LIKE ?)
        """
        s = f'%{search_query}%'
        params.extend([s, s, s, s])
    sql += f" ORDER BY {sort_sql} {order}"

    parties_list = db.execute(sql, params).fetchall()
    return render_template('parties.html', parties=parties_list, active_page='parties')


@app.route('/events')
def events():
    db = get_db()
    events_list = db.execute("""
        SELECT d.deploymentName as name, d.status, d.priority,
               d.startedAt as startDate, d.stoppedAt as endDate,
               cl.firstName || ' ' || cl.lastName as orgName,
               COALESCE(res.serialNumber, 'Multi-resource') as roomNumber,
               COALESCE(p.projectName, '') as description
        FROM deployment d
        JOIN reservation r ON d.reservationId = r.reservationId
        JOIN client cl ON r.clientId = cl.clientId
        LEFT JOIN deployment_resource dr ON d.deploymentId = dr.deploymentId
            AND dr.deallocatedAt IS NULL
        LEFT JOIN resource res ON dr.resourceId = res.resourceId
        LEFT JOIN project p ON d.projectId = p.projectId
        GROUP BY d.deploymentId
        ORDER BY d.startedAt DESC
    """).fetchall()
    return render_template('events.html', events=events_list, active_page='events')


@app.route('/billing')
def billing():
    db = get_db()
    accounts = db.execute("""
        SELECT ba.billingAccountId as accountId, ba.status, ba.accountName,
               COALESCE(o.orgName, cl.firstName || ' ' || cl.lastName) as responsibleParty,
               ROUND(SUM(c.amount), 2) as total_balance
        FROM billing_account ba
        LEFT JOIN organization o ON ba.orgId = o.orgId
        LEFT JOIN client cl ON ba.clientId = cl.clientId
        LEFT JOIN charge c ON ba.billingAccountId = c.billingAccountId
        GROUP BY ba.billingAccountId
    """).fetchall()
    return render_template('billing.html', accounts=accounts, active_page='billing')


@app.route('/reports')
def reports():
    db = get_db()

    report_revenuetop10 = db.execute("""
        SELECT cl.clientId as partyId,
               cl.firstName || ' ' || cl.lastName as partyName,
               COUNT(DISTINCT d.deploymentId) as stays,
               ROUND(SUM(c.amount), 2) as totalSpent
        FROM client cl
        JOIN reservation r ON cl.clientId = r.clientId
        JOIN deployment d ON r.reservationId = d.reservationId
        JOIN charge c ON d.deploymentId = c.deploymentId
        GROUP BY cl.clientId
        ORDER BY totalSpent DESC
        LIMIT 10
    """).fetchall()

    report_util = db.execute("""
        SELECT rt.typeName as room_type,
               COUNT(DISTINCT res.resourceId) as total_rooms,
               SUM(CASE WHEN res.status = 'in-use' THEN 1 ELSE 0 END) as occupied_count
        FROM resource res
        JOIN resource_type rt ON res.resourceTypeId = rt.resourceTypeId
        GROUP BY rt.typeName
    """).fetchall()

    report_monthly = db.execute("""
        SELECT strftime('%Y-%m', chargedAt) as month,
               ROUND(SUM(amount), 2) as total_rev
        FROM charge
        WHERE isProvisional = 0
        GROUP BY month ORDER BY month ASC
    """).fetchall()

    report_service = db.execute("""
        SELECT st.serviceName as serviceCode, ROUND(SUM(c.amount), 2) as total
        FROM charge c
        JOIN service_type st ON c.serviceTypeId = st.serviceTypeId
        GROUP BY st.serviceName
        ORDER BY total DESC
    """).fetchall()

    report_cancel = db.execute("""
        SELECT strftime('%Y-%m', startedAt) as month,
               COUNT(*) as total_resv,
               SUM(CASE WHEN status = 'terminated' THEN 1 ELSE 0 END) as cancelled_count
        FROM deployment
        GROUP BY month ORDER BY month DESC
    """).fetchall()

    report_demographics = db.execute("""
        SELECT CASE WHEN ba.orgId IS NOT NULL THEN 'Organization' ELSE 'Individual' END as party_type,
               COUNT(DISTINCT ba.billingAccountId) as active_accounts,
               ROUND(AVG(total_amt), 2) as avg_spend
        FROM billing_account ba
        JOIN (SELECT billingAccountId, SUM(amount) as total_amt
              FROM charge GROUP BY billingAccountId) c
            ON ba.billingAccountId = c.billingAccountId
        GROUP BY party_type
    """).fetchall()

    report_average_stay = db.execute("""
        SELECT rt.typeName as room_type,
               ROUND(AVG(
                   julianday(COALESCE(d.stoppedAt, '2026-03-31')) - julianday(d.startedAt)
               ), 1) as avg_stay
        FROM deployment d
        JOIN deployment_resource dr ON d.deploymentId = dr.deploymentId
        JOIN resource res ON dr.resourceId = res.resourceId
        JOIN resource_type rt ON res.resourceTypeId = rt.resourceTypeId
        GROUP BY rt.typeName ORDER BY avg_stay DESC
    """).fetchall()

    report_peak_occupancy = db.execute("""
        SELECT strftime('%w', startTime) AS weekday, COUNT(*) AS reservations
        FROM reservation WHERE status != 'cancelled'
        GROUP BY weekday ORDER BY weekday
    """).fetchall()

    c1_labels = [row['month'] for row in report_monthly]
    c1_data = [row['total_rev'] for row in report_monthly]

    observation_date = SYSTEM_DATE
    c2_labels = []
    c2_data = []
    for i in range(6, -1, -1):
        target_date = observation_date - timedelta(days=i)
        t_str = target_date.strftime('%Y-%m-%d')
        cnt = db.execute("""
            SELECT COUNT(*) FROM deployment
            WHERE status = 'active'
            AND startedAt <= ? AND (stoppedAt IS NULL OR stoppedAt > ?)
        """, (t_str, t_str)).fetchone()[0]
        c2_labels.append(target_date.strftime('%m-%d'))
        c2_data.append(cnt)

    c3_labels = [row['serviceCode'] for row in report_service]
    c3_data = [row['total'] for row in report_service]
    c4_labels = [row['party_type'] for row in report_demographics]
    c4_data = [row['active_accounts'] for row in report_demographics]

    trend_direction = 'flat'
    if len(report_monthly) >= 2:
        trend_direction = 'up' if report_monthly[-1]['total_rev'] >= report_monthly[-2]['total_rev'] else 'down'

    return render_template('reports.html',
                           report_revenue=report_revenuetop10,
                           report_util=report_util, report_monthly=report_monthly,
                           report_service=report_service, report_cancel=report_cancel,
                           report_demographics=report_demographics,
                           report_average_stay=report_average_stay,
                           report_peak_occupancy=report_peak_occupancy,
                           c1_labels=c1_labels, c1_data=c1_data,
                           c2_labels=c2_labels, c2_data=c2_data,
                           c3_labels=c3_labels, c3_data=c3_data,
                           c4_labels=c4_labels, c4_data=c4_data,
                           trend_direction=trend_direction, active_page='reports')


if __name__ == '__main__':
    app.run(debug=True, port=5000)
