-- CloudNine Systems: Database Implementation

-- Part 1: Schema Definition (DDL)
-- Section 1: Infrastructure

PRAGMA foreign_keys = ON;

CREATE TABLE region (
    regionId        INTEGER PRIMARY KEY AUTOINCREMENT,
    regionName      TEXT NOT NULL UNIQUE,
    connectivity    TEXT NOT NULL,
    regulatoryEnv   TEXT NOT NULL
);

CREATE TABLE availability_zone (
    zoneId          INTEGER PRIMARY KEY AUTOINCREMENT,
    regionId        INTEGER NOT NULL,
    zoneName        TEXT NOT NULL UNIQUE,
    redundancyLevel TEXT NOT NULL,
    status          TEXT NOT NULL DEFAULT 'active',
    FOREIGN KEY (regionId) REFERENCES region(regionId)
);

CREATE TABLE data_center (
    datacenterId    INTEGER PRIMARY KEY AUTOINCREMENT,
    zoneId          INTEGER NOT NULL,
    name            TEXT NOT NULL,
    country         TEXT NOT NULL,
    city            TEXT NOT NULL,
    status          TEXT NOT NULL DEFAULT 'operational',
    FOREIGN KEY (zoneId) REFERENCES availability_zone(zoneId)
);

CREATE TABLE resource_type (
    resourceTypeId  INTEGER PRIMARY KEY AUTOINCREMENT,
    typeName        TEXT NOT NULL UNIQUE,
    category        TEXT NOT NULL,
    baseHourlyRate  REAL NOT NULL,
    performanceTier TEXT NOT NULL,
    maxCapacity     INTEGER NOT NULL
);

CREATE TABLE resource (
    resourceId      INTEGER PRIMARY KEY AUTOINCREMENT,
    resourceTypeId  INTEGER NOT NULL,
    datacenterId    INTEGER NOT NULL,
    serialNumber    TEXT NOT NULL UNIQUE,
    status          TEXT NOT NULL DEFAULT 'available',
    currentConfig   TEXT,
    commissionedAt  TEXT NOT NULL,
    FOREIGN KEY (resourceTypeId) REFERENCES resource_type(resourceTypeId),
    FOREIGN KEY (datacenterId) REFERENCES data_center(datacenterId)
);

CREATE TABLE resource_component (
    componentId       INTEGER PRIMARY KEY AUTOINCREMENT,
    parentResourceId  INTEGER NOT NULL,
    componentType     TEXT NOT NULL,
    specs             TEXT,
    status            TEXT NOT NULL DEFAULT 'active',
    FOREIGN KEY (parentResourceId) REFERENCES resource(resourceId)
);

CREATE TABLE staff (
    staffId     INTEGER PRIMARY KEY AUTOINCREMENT,
    name        TEXT NOT NULL,
    role        TEXT NOT NULL,
    email       TEXT NOT NULL UNIQUE,
    department  TEXT NOT NULL,
    isActive    INTEGER NOT NULL DEFAULT 1,
    createdAt   TEXT NOT NULL
);

CREATE TABLE maintenanceLog (
    maintenanceId   INTEGER PRIMARY KEY AUTOINCREMENT,
    resourceId      INTEGER NOT NULL,
    staffId         INTEGER NOT NULL,
    maintenanceType TEXT NOT NULL,
    isScheduled     INTEGER NOT NULL DEFAULT 1,
    scheduledStart  TEXT NOT NULL,
    scheduledEnd    TEXT NOT NULL,
    actualEnd       TEXT,
    notes           TEXT,
    FOREIGN KEY (resourceId) REFERENCES resource(resourceId),
    FOREIGN KEY (staffId) REFERENCES staff(staffId)
);

-- Section 2: Clients & Users

CREATE TABLE organization (
    orgId        INTEGER PRIMARY KEY AUTOINCREMENT,
    orgName      TEXT NOT NULL UNIQUE,
    industry     TEXT NOT NULL,
    contactEmail TEXT NOT NULL,
    creditRating TEXT NOT NULL DEFAULT 'standard',
    createdAt    TEXT NOT NULL
);

CREATE TABLE team (
    teamId      INTEGER PRIMARY KEY AUTOINCREMENT,
    orgId       INTEGER NOT NULL,
    teamName    TEXT NOT NULL,
    description TEXT,
    createdAt   TEXT NOT NULL,
    FOREIGN KEY (orgId) REFERENCES organization(orgId)
);

CREATE TABLE client (
    clientId    INTEGER PRIMARY KEY AUTOINCREMENT,
    teamId      INTEGER,
    orgId       INTEGER,
    clientType  TEXT NOT NULL DEFAULT 'individual',
    firstName   TEXT NOT NULL,
    lastName    TEXT NOT NULL,
    email       TEXT NOT NULL UNIQUE,
    role        TEXT,
    createdAt   TEXT NOT NULL,
    FOREIGN KEY (teamId) REFERENCES team(teamId),
    FOREIGN KEY (orgId) REFERENCES organization(orgId)
);

-- Section 3: Reservations & Deployments

CREATE TABLE project (
    projectId   INTEGER PRIMARY KEY AUTOINCREMENT,
    clientId    INTEGER NOT NULL,
    projectName TEXT NOT NULL,
    description TEXT,
    createdAt   TEXT NOT NULL,
    FOREIGN KEY (clientId) REFERENCES client(clientId)
);

CREATE TABLE reservation (
    reservationId   INTEGER PRIMARY KEY AUTOINCREMENT,
    clientId        INTEGER NOT NULL,
    projectId       INTEGER,
    startTime       TEXT NOT NULL,
    endTime         TEXT NOT NULL,
    status          TEXT NOT NULL DEFAULT 'pending',
    priority        TEXT NOT NULL DEFAULT 'standard',
    depositAmount   REAL DEFAULT 0,
    FOREIGN KEY (clientId) REFERENCES client(clientId),
    FOREIGN KEY (projectId) REFERENCES project(projectId)
);

CREATE TABLE reservation_resource (
    resResourceId   INTEGER PRIMARY KEY AUTOINCREMENT,
    reservationId   INTEGER NOT NULL,
    resourceId      INTEGER NOT NULL,
    requestedConfig TEXT,
    assignedAt      TEXT,
    FOREIGN KEY (reservationId) REFERENCES reservation(reservationId),
    FOREIGN KEY (resourceId) REFERENCES resource(resourceId)
);

CREATE TABLE deployment (
    deploymentId    INTEGER PRIMARY KEY AUTOINCREMENT,
    reservationId   INTEGER NOT NULL,
    projectId       INTEGER,
    deploymentName  TEXT NOT NULL,
    status          TEXT NOT NULL DEFAULT 'active',
    priority        TEXT NOT NULL DEFAULT 'standard',
    startedAt       TEXT NOT NULL,
    stoppedAt       TEXT,
    autoScale       INTEGER NOT NULL DEFAULT 0,
    FOREIGN KEY (reservationId) REFERENCES reservation(reservationId),
    FOREIGN KEY (projectId) REFERENCES project(projectId)
);

CREATE TABLE deployment_resource (
    depResourceId   INTEGER PRIMARY KEY AUTOINCREMENT,
    deploymentId    INTEGER NOT NULL,
    resourceId      INTEGER NOT NULL,
    allocatedAt     TEXT NOT NULL,
    deallocatedAt   TEXT,
    usageHours      REAL,
    FOREIGN KEY (deploymentId) REFERENCES deployment(deploymentId),
    FOREIGN KEY (resourceId) REFERENCES resource(resourceId)
);

CREATE TABLE scaling_event (
    scalingEventId  INTEGER PRIMARY KEY AUTOINCREMENT,
    deploymentId    INTEGER NOT NULL,
    staffId         INTEGER,
    eventType       TEXT NOT NULL,
    previousScale   INTEGER NOT NULL,
    newScale        INTEGER NOT NULL,
    triggeredAt     TEXT NOT NULL,
    FOREIGN KEY (deploymentId) REFERENCES deployment(deploymentId),
    FOREIGN KEY (staffId) REFERENCES staff(staffId)
);

CREATE TABLE deployment_event (
    eventId         INTEGER PRIMARY KEY AUTOINCREMENT,
    deploymentId    INTEGER NOT NULL,
    staffId         INTEGER,
    eventType       TEXT NOT NULL,
    timestamp       TEXT NOT NULL,
    notes           TEXT,
    FOREIGN KEY (deploymentId) REFERENCES deployment(deploymentId),
    FOREIGN KEY (staffId) REFERENCES staff(staffId)
);

-- Section 4: Billing & Charges

CREATE TABLE billing_account (
    billingAccountId INTEGER PRIMARY KEY AUTOINCREMENT,
    orgId            INTEGER,
    clientId         INTEGER,
    accountName      TEXT NOT NULL,
    paymentMethod    TEXT NOT NULL,
    creditLimit      REAL NOT NULL DEFAULT 10000,
    status           TEXT NOT NULL DEFAULT 'active',
    FOREIGN KEY (orgId) REFERENCES organization(orgId),
    FOREIGN KEY (clientId) REFERENCES client(clientId),
    CHECK (orgId IS NOT NULL OR clientId IS NOT NULL)
);

CREATE TABLE cost_center (
    costCenterId     INTEGER PRIMARY KEY AUTOINCREMENT,
    billingAccountId INTEGER NOT NULL,
    centerName       TEXT NOT NULL,
    budgetLimit      REAL,
    FOREIGN KEY (billingAccountId) REFERENCES billing_account(billingAccountId)
);

CREATE TABLE service_type (
    serviceTypeId   INTEGER PRIMARY KEY AUTOINCREMENT,
    serviceName     TEXT NOT NULL UNIQUE,
    category        TEXT NOT NULL,
    unitOfMeasure   TEXT NOT NULL,
    defaultRate     REAL NOT NULL
);

CREATE TABLE invoice (
    invoiceId        INTEGER PRIMARY KEY AUTOINCREMENT,
    billingAccountId INTEGER NOT NULL,
    periodStart      TEXT NOT NULL,
    periodEnd        TEXT NOT NULL,
    totalAmount      REAL NOT NULL,
    status           TEXT NOT NULL DEFAULT 'pending',
    issuedAt         TEXT NOT NULL,
    dueAt            TEXT NOT NULL,
    FOREIGN KEY (billingAccountId) REFERENCES billing_account(billingAccountId)
);

CREATE TABLE charge (
    chargeId         INTEGER PRIMARY KEY AUTOINCREMENT,
    serviceTypeId    INTEGER NOT NULL,
    billingAccountId INTEGER NOT NULL,
    deploymentId     INTEGER NOT NULL,
    invoiceId        INTEGER,
    amount           REAL NOT NULL,
    status           TEXT NOT NULL DEFAULT 'finalized',
    isProvisional    INTEGER NOT NULL DEFAULT 0,
    chargedAt        TEXT NOT NULL,
    FOREIGN KEY (serviceTypeId) REFERENCES service_type(serviceTypeId),
    FOREIGN KEY (billingAccountId) REFERENCES billing_account(billingAccountId),
    FOREIGN KEY (deploymentId) REFERENCES deployment(deploymentId),
    FOREIGN KEY (invoiceId) REFERENCES invoice(invoiceId)
);

CREATE TABLE charge_allocation (
    allocationId    INTEGER PRIMARY KEY AUTOINCREMENT,
    chargeId        INTEGER NOT NULL,
    costCenterId    INTEGER NOT NULL,
    percentage      REAL NOT NULL,
    amount          REAL NOT NULL,
    FOREIGN KEY (chargeId) REFERENCES charge(chargeId),
    FOREIGN KEY (costCenterId) REFERENCES cost_center(costCenterId)
);

CREATE TABLE adjustment (
    adjustmentId    INTEGER PRIMARY KEY AUTOINCREMENT,
    chargeId        INTEGER NOT NULL,
    staffId         INTEGER NOT NULL,
    adjustmentType  TEXT NOT NULL,
    amount          REAL NOT NULL,
    reason          TEXT NOT NULL,
    createdAt       TEXT NOT NULL,
    FOREIGN KEY (chargeId) REFERENCES charge(chargeId),
    FOREIGN KEY (staffId) REFERENCES staff(staffId)
);

-- Section 5: Access & Security

CREATE TABLE credential (
    credentialId    INTEGER PRIMARY KEY AUTOINCREMENT,
    clientId        INTEGER NOT NULL,
    credentialType  TEXT NOT NULL,
    isActive        INTEGER NOT NULL DEFAULT 1,
    createdAt       TEXT NOT NULL,
    expiresAt       TEXT,
    FOREIGN KEY (clientId) REFERENCES client(clientId)
);

CREATE TABLE accessLog (
    accessLogId     INTEGER PRIMARY KEY AUTOINCREMENT,
    clientId        INTEGER NOT NULL,
    resourceId      INTEGER NOT NULL,
    deploymentId    INTEGER,
    credentialId    INTEGER,
    action          TEXT NOT NULL,
    ipAddress       TEXT NOT NULL,
    loggedAt        TEXT NOT NULL,
    FOREIGN KEY (clientId) REFERENCES client(clientId),
    FOREIGN KEY (resourceId) REFERENCES resource(resourceId),
    FOREIGN KEY (deploymentId) REFERENCES deployment(deploymentId),
    FOREIGN KEY (credentialId) REFERENCES credential(credentialId)
);

-- Part 2: Sample Data (DML)

-- Infrastructure Data

-- 3 regions
INSERT INTO region VALUES (1, 'US-East', 'high-bandwidth', 'US federal');
INSERT INTO region VALUES (2, 'US-West', 'high-bandwidth', 'US federal');
INSERT INTO region VALUES (3, 'EU-West', 'standard', 'GDPR');

-- 6 availability zones (2 per region)
INSERT INTO availability_zone VALUES (1, 1, 'us-east-1a', 'dual-power', 'active');
INSERT INTO availability_zone VALUES (2, 1, 'us-east-1b', 'dual-power', 'active');
INSERT INTO availability_zone VALUES (3, 2, 'us-west-2a', 'dual-power', 'active');
INSERT INTO availability_zone VALUES (4, 2, 'us-west-2b', 'standard', 'active');
INSERT INTO availability_zone VALUES (5, 3, 'eu-west-1a', 'dual-power', 'active');
INSERT INTO availability_zone VALUES (6, 3, 'eu-west-1b', 'standard', 'active');

-- 12 data centers (2 per AZ)
INSERT INTO data_center VALUES (1,  1, 'DC-Virginia-1',    'US', 'Ashburn',    'operational');
INSERT INTO data_center VALUES (2,  1, 'DC-Virginia-2',    'US', 'Ashburn',    'operational');
INSERT INTO data_center VALUES (3,  2, 'DC-Virginia-3',    'US', 'Richmond',   'operational');
INSERT INTO data_center VALUES (4,  2, 'DC-Virginia-4',    'US', 'Richmond',   'operational');
INSERT INTO data_center VALUES (5,  3, 'DC-Oregon-1',      'US', 'Portland',   'operational');
INSERT INTO data_center VALUES (6,  3, 'DC-Oregon-2',      'US', 'Portland',   'operational');
INSERT INTO data_center VALUES (7,  4, 'DC-Oregon-3',      'US', 'Salem',      'operational');
INSERT INTO data_center VALUES (8,  4, 'DC-Oregon-4',      'US', 'Salem',      'maintenance');
INSERT INTO data_center VALUES (9,  5, 'DC-Ireland-1',     'IE', 'Dublin',     'operational');
INSERT INTO data_center VALUES (10, 5, 'DC-Ireland-2',     'IE', 'Dublin',     'operational');
INSERT INTO data_center VALUES (11, 6, 'DC-Frankfurt-1',   'DE', 'Frankfurt',  'operational');
INSERT INTO data_center VALUES (12, 6, 'DC-Frankfurt-2',   'DE', 'Frankfurt',  'operational');

-- 6 resource types
INSERT INTO resource_type VALUES (1, 'General Compute',        'compute',  0.50,  'standard',    64);
INSERT INTO resource_type VALUES (2, 'High-Memory Compute',    'compute',  1.20,  'premium',     256);
INSERT INTO resource_type VALUES (3, 'GPU Compute',            'compute',  3.50,  'premium',     8);
INSERT INTO resource_type VALUES (4, 'Standard Storage',       'storage',  0.10,  'standard',    10000);
INSERT INTO resource_type VALUES (5, 'High-Perf Storage',      'storage',  0.35,  'premium',     5000);
INSERT INTO resource_type VALUES (6, 'Network Load Balancer',  'network',  0.25,  'standard',    1000);

-- 42 resources spread across data centers
-- US-East (DC 1-4): 18 resources
INSERT INTO resource VALUES (1,  1, 1, 'SN-GC-0001', 'in-use',    '4 vCPU / 16GB',  '2025-06-01');
INSERT INTO resource VALUES (2,  1, 1, 'SN-GC-0002', 'in-use',    '4 vCPU / 16GB',  '2025-06-01');
INSERT INTO resource VALUES (3,  1, 1, 'SN-GC-0003', 'available', '8 vCPU / 32GB',  '2025-07-15');
INSERT INTO resource VALUES (4,  2, 1, 'SN-HM-0001', 'in-use',    '16 vCPU / 128GB', '2025-06-01');
INSERT INTO resource VALUES (5,  2, 2, 'SN-HM-0002', 'in-use',    '16 vCPU / 128GB', '2025-08-01');
INSERT INTO resource VALUES (6,  3, 2, 'SN-GP-0001', 'in-use',    '4x A100 GPU',     '2025-09-01');
INSERT INTO resource VALUES (7,  3, 2, 'SN-GP-0002', 'available', '4x A100 GPU',     '2025-09-01');
INSERT INTO resource VALUES (8,  4, 3, 'SN-SS-0001', 'in-use',    '5TB SSD',         '2025-06-01');
INSERT INTO resource VALUES (9,  4, 3, 'SN-SS-0002', 'in-use',    '5TB SSD',         '2025-06-01');
INSERT INTO resource VALUES (10, 5, 3, 'SN-HP-0001', 'in-use',    '2TB NVMe',        '2025-07-01');
INSERT INTO resource VALUES (11, 6, 4, 'SN-NL-0001', 'in-use',    'L7 balancer',     '2025-06-01');
INSERT INTO resource VALUES (12, 6, 4, 'SN-NL-0002', 'available', 'L7 balancer',     '2025-06-01');
INSERT INTO resource VALUES (13, 1, 1, 'SN-GC-0004', 'in-use',    '8 vCPU / 32GB',  '2025-10-01');
INSERT INTO resource VALUES (14, 1, 2, 'SN-GC-0005', 'in-use',    '4 vCPU / 16GB',  '2025-10-01');
INSERT INTO resource VALUES (15, 2, 3, 'SN-HM-0003', 'available', '32 vCPU / 256GB', '2025-11-01');
INSERT INTO resource VALUES (16, 4, 4, 'SN-SS-0003', 'in-use',    '10TB SSD',        '2025-11-01');
INSERT INTO resource VALUES (17, 1, 2, 'SN-GC-0006', 'maintenance','4 vCPU / 16GB',  '2025-08-01');
INSERT INTO resource VALUES (18, 5, 1, 'SN-HP-0002', 'in-use',    '2TB NVMe',        '2025-12-01');

-- US-West (DC 5-8): 12 resources
INSERT INTO resource VALUES (19, 1, 5, 'SN-GC-0007', 'in-use',    '4 vCPU / 16GB',  '2025-06-01');
INSERT INTO resource VALUES (20, 1, 5, 'SN-GC-0008', 'in-use',    '8 vCPU / 32GB',  '2025-07-01');
INSERT INTO resource VALUES (21, 2, 6, 'SN-HM-0004', 'in-use',    '16 vCPU / 128GB', '2025-06-01');
INSERT INTO resource VALUES (22, 3, 6, 'SN-GP-0003', 'in-use',    '8x A100 GPU',     '2025-09-01');
INSERT INTO resource VALUES (23, 4, 7, 'SN-SS-0004', 'in-use',    '5TB SSD',         '2025-06-01');
INSERT INTO resource VALUES (24, 4, 7, 'SN-SS-0005', 'available', '5TB SSD',         '2025-08-01');
INSERT INTO resource VALUES (25, 6, 5, 'SN-NL-0003', 'in-use',    'L4 balancer',     '2025-06-01');
INSERT INTO resource VALUES (26, 1, 6, 'SN-GC-0009', 'available', '4 vCPU / 16GB',  '2025-10-01');
INSERT INTO resource VALUES (27, 5, 7, 'SN-HP-0003', 'in-use',    '4TB NVMe',        '2025-10-01');
INSERT INTO resource VALUES (28, 1, 5, 'SN-GC-0010', 'in-use',    '8 vCPU / 32GB',  '2025-11-01');
INSERT INTO resource VALUES (29, 3, 6, 'SN-GP-0004', 'available', '4x A100 GPU',     '2025-12-01');
INSERT INTO resource VALUES (30, 2, 5, 'SN-HM-0005', 'in-use',    '32 vCPU / 256GB', '2025-12-01');

-- EU-West (DC 9-12): 12 resources
INSERT INTO resource VALUES (31, 1, 9,  'SN-GC-0011', 'in-use',    '4 vCPU / 16GB',  '2025-06-01');
INSERT INTO resource VALUES (32, 1, 9,  'SN-GC-0012', 'in-use',    '8 vCPU / 32GB',  '2025-07-01');
INSERT INTO resource VALUES (33, 2, 10, 'SN-HM-0006', 'in-use',    '16 vCPU / 128GB', '2025-08-01');
INSERT INTO resource VALUES (34, 3, 10, 'SN-GP-0005', 'in-use',    '4x A100 GPU',     '2025-09-01');
INSERT INTO resource VALUES (35, 4, 11, 'SN-SS-0006', 'in-use',    '5TB SSD',         '2025-06-01');
INSERT INTO resource VALUES (36, 4, 11, 'SN-SS-0007', 'in-use',    '10TB SSD',        '2025-06-01');
INSERT INTO resource VALUES (37, 5, 12, 'SN-HP-0004', 'available', '2TB NVMe',        '2025-07-01');
INSERT INTO resource VALUES (38, 6, 9,  'SN-NL-0004', 'in-use',    'L7 balancer',     '2025-06-01');
INSERT INTO resource VALUES (39, 1, 10, 'SN-GC-0013', 'available', '4 vCPU / 16GB',  '2025-10-01');
INSERT INTO resource VALUES (40, 2, 11, 'SN-HM-0007', 'in-use',    '16 vCPU / 128GB', '2025-11-01');
INSERT INTO resource VALUES (41, 1, 12, 'SN-GC-0014', 'in-use',    '8 vCPU / 32GB',  '2025-12-01');
INSERT INTO resource VALUES (42, 4, 12, 'SN-SS-0008', 'in-use',    '5TB SSD',         '2025-12-01');

-- Resource components (minimal, per professor feedback)
INSERT INTO resource_component VALUES (1, 6,  'GPU Module',   '4x NVIDIA A100 80GB', 'active');
INSERT INTO resource_component VALUES (2, 6,  'NVLink Bridge', 'NVLink 3.0',          'active');
INSERT INTO resource_component VALUES (3, 22, 'GPU Module',   '8x NVIDIA A100 80GB', 'active');
INSERT INTO resource_component VALUES (4, 22, 'NVLink Bridge', 'NVLink 3.0',          'active');

-- Staff Data

INSERT INTO staff VALUES (1, 'Maria Chen',       'operations engineer',  'maria.chen@cloudnine.com',     'Operations',   1, '2024-01-15');
INSERT INTO staff VALUES (2, 'James Rivera',      'systems engineer',     'james.rivera@cloudnine.com',   'Engineering',  1, '2024-02-01');
INSERT INTO staff VALUES (3, 'Sarah Kim',         'billing specialist',   'sarah.kim@cloudnine.com',      'Finance',      1, '2024-03-10');
INSERT INTO staff VALUES (4, 'David Park',        'support engineer',     'david.park@cloudnine.com',     'Support',      1, '2024-01-20');
INSERT INTO staff VALUES (5, 'Emily Santos',      'operations manager',   'emily.santos@cloudnine.com',   'Operations',   1, '2023-11-01');
INSERT INTO staff VALUES (6, 'Alex Thompson',     'network engineer',     'alex.thompson@cloudnine.com',  'Engineering',  1, '2024-04-15');
INSERT INTO staff VALUES (7, 'Rachel Nguyen',     'account manager',      'rachel.nguyen@cloudnine.com',  'Sales',        1, '2024-05-01');
INSERT INTO staff VALUES (8, 'Michael Foster',    'datacenter technician','michael.foster@cloudnine.com', 'Operations',   0, '2024-01-10');

-- Maintenance logs (10 entries across Q1)
INSERT INTO maintenanceLog VALUES (1,  17, 2, 'hardware repair',     0, '2026-01-05', '2026-01-06', '2026-01-06', 'Failed memory module replaced');
INSERT INTO maintenanceLog VALUES (2,  8,  1, 'firmware update',     1, '2026-01-10', '2026-01-10', '2026-01-10', 'Storage controller firmware v3.2');
INSERT INTO maintenanceLog VALUES (3,  11, 6, 'health check',        1, '2026-01-15', '2026-01-15', '2026-01-15', 'Quarterly load balancer inspection');
INSERT INTO maintenanceLog VALUES (4,  22, 2, 'GPU diagnostics',     1, '2026-02-01', '2026-02-01', '2026-02-02', 'Extended thermal testing on GPU cluster');
INSERT INTO maintenanceLog VALUES (5,  6,  2, 'cooling repair',      0, '2026-02-10', '2026-02-11', '2026-02-11', 'Fan unit replaced in GPU rack');
INSERT INTO maintenanceLog VALUES (6,  35, 1, 'disk replacement',    0, '2026-02-15', '2026-02-15', '2026-02-16', 'Predictive failure on disk 3, replaced');
INSERT INTO maintenanceLog VALUES (7,  25, 6, 'firmware update',     1, '2026-02-20', '2026-02-20', '2026-02-20', 'Network balancer firmware v2.8');
INSERT INTO maintenanceLog VALUES (8,  38, 6, 'health check',        1, '2026-03-01', '2026-03-01', '2026-03-01', 'Quarterly load balancer inspection');
INSERT INTO maintenanceLog VALUES (9,  13, 1, 'hardware upgrade',    1, '2026-03-10', '2026-03-10', '2026-03-10', 'RAM upgrade 16GB to 32GB');
INSERT INTO maintenanceLog VALUES (10, 33, 2, 'firmware update',     1, '2026-03-15', '2026-03-15', '2026-03-15', 'Memory controller update');

-- Clients & Users Data

-- 6 organizations
INSERT INTO organization VALUES (1, 'Meridian Analytics',   'data analytics',    'admin@meridian.io',     'premium',   '2024-06-01');
INSERT INTO organization VALUES (2, 'Quantum Health',       'healthcare',        'ops@quantumhealth.com', 'premium',   '2024-07-15');
INSERT INTO organization VALUES (3, 'NovaCraft Games',      'gaming',            'infra@novacraft.gg',    'standard',  '2024-09-01');
INSERT INTO organization VALUES (4, 'Terraform Labs',       'research',          'admin@terraform.edu',   'academic',  '2025-01-10');
INSERT INTO organization VALUES (5, 'Pinnacle Media',       'media',             'tech@pinnacle.tv',      'standard',  '2025-03-01');
INSERT INTO organization VALUES (6, 'Greenline Logistics',  'logistics',         'cloud@greenline.co',    'premium',   '2025-05-20');

-- 12 teams (2 per org)
INSERT INTO team VALUES (1,  1, 'Data Pipeline',       'ETL and data processing',       '2024-06-01');
INSERT INTO team VALUES (2,  1, 'ML Research',         'Machine learning models',        '2024-06-01');
INSERT INTO team VALUES (3,  2, 'Patient Systems',     'EHR and patient data',           '2024-07-15');
INSERT INTO team VALUES (4,  2, 'Compliance',          'HIPAA and regulatory',           '2024-07-15');
INSERT INTO team VALUES (5,  3, 'Game Servers',        'Live multiplayer backend',       '2024-09-01');
INSERT INTO team VALUES (6,  3, 'QA Testing',          'Automated testing infra',        '2024-09-01');
INSERT INTO team VALUES (7,  4, 'Genomics',            'DNA sequencing pipelines',       '2025-01-10');
INSERT INTO team VALUES (8,  4, 'Climate Modeling',    'Weather simulation',             '2025-01-10');
INSERT INTO team VALUES (9,  5, 'Streaming',           'Video encoding and CDN',         '2025-03-01');
INSERT INTO team VALUES (10, 5, 'Ad Platform',         'Real-time ad serving',           '2025-03-01');
INSERT INTO team VALUES (11, 6, 'Route Optimization',  'Fleet routing algorithms',       '2025-05-20');
INSERT INTO team VALUES (12, 6, 'Warehouse Systems',   'Inventory tracking',             '2025-05-20');

-- 20 clients (mix of team members and freelancers)
INSERT INTO client VALUES (1,  1,  1,    'team_member', 'Lena',    'Okafor',    'lena@meridian.io',        'lead engineer',  '2024-06-01');
INSERT INTO client VALUES (2,  2,  1,    'team_member', 'Ravi',    'Sharma',    'ravi@meridian.io',        'ML engineer',    '2024-06-15');
INSERT INTO client VALUES (3,  3,  2,    'team_member', 'Diana',   'Morales',   'diana@quantumhealth.com', 'senior dev',     '2024-07-15');
INSERT INTO client VALUES (4,  4,  2,    'team_member', 'Tom',     'Chen',      'tom@quantumhealth.com',   'compliance eng', '2024-08-01');
INSERT INTO client VALUES (5,  5,  3,    'team_member', 'Yuki',    'Tanaka',    'yuki@novacraft.gg',       'infra lead',     '2024-09-01');
INSERT INTO client VALUES (6,  6,  3,    'team_member', 'Jake',    'Williams',  'jake@novacraft.gg',       'QA engineer',    '2024-09-15');
INSERT INTO client VALUES (7,  7,  4,    'team_member', 'Priya',   'Patel',     'priya@terraform.edu',     'postdoc',        '2025-01-10');
INSERT INTO client VALUES (8,  8,  4,    'team_member', 'Marco',   'Rossi',     'marco@terraform.edu',     'researcher',     '2025-01-20');
INSERT INTO client VALUES (9,  9,  5,    'team_member', 'Aisha',   'Rahman',    'aisha@pinnacle.tv',       'streaming eng',  '2025-03-01');
INSERT INTO client VALUES (10, 10, 5,    'team_member', 'Chris',   'Lee',       'chris@pinnacle.tv',       'ad tech lead',   '2025-03-15');
INSERT INTO client VALUES (11, 11, 6,    'team_member', 'Sofia',   'Alvarez',   'sofia@greenline.co',      'algo engineer',  '2025-05-20');
INSERT INTO client VALUES (12, 12, 6,    'team_member', 'Nate',    'Brooks',    'nate@greenline.co',       'backend dev',    '2025-06-01');
INSERT INTO client VALUES (13, 1,  1,    'team_member', 'Ethan',   'Wright',    'ethan@meridian.io',       'data engineer',  '2025-02-01');
INSERT INTO client VALUES (14, 5,  3,    'team_member', 'Mia',     'Johnson',   'mia@novacraft.gg',        'devops',         '2025-04-01');
-- Freelancers (no team, direct org or fully independent)
INSERT INTO client VALUES (15, NULL, 4,  'individual',  'Omar',    'Hassan',    'omar.hassan@gmail.com',   'consultant',     '2025-06-01');
INSERT INTO client VALUES (16, NULL, NULL,'individual', 'Zoe',     'Fischer',   'zoe.fischer@outlook.com', 'indie dev',      '2025-07-01');
INSERT INTO client VALUES (17, NULL, NULL,'individual', 'Lucas',   'Duarte',    'lucas.d@proton.me',       'freelance ML',   '2025-08-15');
INSERT INTO client VALUES (18, 7,  4,    'team_member', 'Fatima',  'Ali',       'fatima@terraform.edu',    'PhD student',    '2025-09-01');
INSERT INTO client VALUES (19, 9,  5,    'team_member', 'Ben',     'Carter',    'ben@pinnacle.tv',         'video engineer', '2025-10-01');
INSERT INTO client VALUES (20, NULL, 6,  'individual',  'Hannah',  'Mueller',   'hannah@greenline.co',     'data analyst',   '2025-11-01');

-- Projects Data

INSERT INTO project VALUES (1,  1,  'Customer 360 Pipeline',   'Real-time customer data pipeline',                  '2025-11-01');
INSERT INTO project VALUES (2,  2,  'Fraud Detection Model',   'ML model for transaction fraud scoring',            '2025-11-15');
INSERT INTO project VALUES (3,  3,  'EHR Migration',           'Migrating patient records to new platform',         '2025-12-01');
INSERT INTO project VALUES (4,  5,  'Season 4 Launch',         'Game server infra for new season release',          '2025-12-15');
INSERT INTO project VALUES (5,  7,  'Genome Assembly v2',      'Next-gen DNA assembly pipeline',                    '2025-12-20');
INSERT INTO project VALUES (6,  9,  'Live 4K Streaming',       'Ultra-HD live streaming infrastructure',            '2026-01-05');
INSERT INTO project VALUES (7,  11, 'Route Engine Rebuild',    'Rewrite of fleet optimization algorithm',           '2026-01-10');
INSERT INTO project VALUES (8,  8,  'Arctic Climate Sim',      'Arctic ice sheet simulation for 2026 forecast',     '2026-01-15');
INSERT INTO project VALUES (9,  16, 'Indie Game Backend',      'Multiplayer backend for indie title',               '2026-01-20');
INSERT INTO project VALUES (10, 17, 'NLP Research',            'Large language model fine-tuning experiments',       '2026-02-01');
INSERT INTO project VALUES (11, 10, 'Programmatic Ads v3',     'Real-time bidding platform upgrade',                '2026-02-10');
INSERT INTO project VALUES (12, 12, 'Warehouse Tracker',       'Real-time inventory management system',             '2026-02-15');

-- Reservations Data (20 reservations across Q1)

INSERT INTO reservation VALUES (1,  1,  1,    '2026-01-01', '2026-03-31', 'confirmed', 'high',     500.00);
INSERT INTO reservation VALUES (2,  2,  2,    '2026-01-05', '2026-03-31', 'confirmed', 'high',     750.00);
INSERT INTO reservation VALUES (3,  3,  3,    '2026-01-10', '2026-04-30', 'confirmed', 'critical', 1000.00);
INSERT INTO reservation VALUES (4,  5,  4,    '2026-01-15', '2026-02-28', 'completed', 'high',     300.00);
INSERT INTO reservation VALUES (5,  7,  5,    '2026-01-15', '2026-03-31', 'confirmed', 'standard', 0.00);
INSERT INTO reservation VALUES (6,  9,  6,    '2026-01-20', '2026-03-31', 'confirmed', 'high',     400.00);
INSERT INTO reservation VALUES (7,  11, 7,    '2026-01-25', '2026-03-31', 'confirmed', 'standard', 0.00);
INSERT INTO reservation VALUES (8,  8,  8,    '2026-02-01', '2026-03-31', 'confirmed', 'standard', 0.00);
INSERT INTO reservation VALUES (9,  16, 9,    '2026-02-01', '2026-02-28', 'completed', 'standard', 100.00);
INSERT INTO reservation VALUES (10, 17, 10,   '2026-02-05', '2026-03-15', 'completed', 'standard', 200.00);
INSERT INTO reservation VALUES (11, 10, 11,   '2026-02-10', '2026-03-31', 'confirmed', 'high',     350.00);
INSERT INTO reservation VALUES (12, 12, 12,   '2026-02-15', '2026-03-31', 'confirmed', 'standard', 0.00);
INSERT INTO reservation VALUES (13, 4,  3,    '2026-02-20', '2026-03-31', 'confirmed', 'critical', 0.00);
INSERT INTO reservation VALUES (14, 6,  NULL, '2026-02-25', '2026-03-15', 'completed', 'standard', 0.00);
INSERT INTO reservation VALUES (15, 13, 1,    '2026-03-01', '2026-03-31', 'confirmed', 'standard', 0.00);
INSERT INTO reservation VALUES (16, 14, 4,    '2026-03-01', '2026-03-31', 'confirmed', 'standard', 0.00);
INSERT INTO reservation VALUES (17, 15, 5,    '2026-03-05', '2026-04-30', 'confirmed', 'standard', 0.00);
INSERT INTO reservation VALUES (18, 19, 6,    '2026-03-10', '2026-03-31', 'confirmed', 'high',     250.00);
INSERT INTO reservation VALUES (19, 20, 12,   '2026-03-15', '2026-03-31', 'confirmed', 'standard', 0.00);
INSERT INTO reservation VALUES (20, 18, 8,    '2026-03-20', '2026-04-30', 'confirmed', 'standard', 0.00);

-- Reservation resources (which resources are assigned to each reservation)
INSERT INTO reservation_resource VALUES (1,  1,  1,  '8 vCPU / 32GB',   '2025-12-28');
INSERT INTO reservation_resource VALUES (2,  1,  8,  '5TB SSD',         '2025-12-28');
INSERT INTO reservation_resource VALUES (3,  1,  11, 'L7 balancer',     '2025-12-28');
INSERT INTO reservation_resource VALUES (4,  2,  6,  '4x A100 GPU',     '2026-01-02');
INSERT INTO reservation_resource VALUES (5,  2,  10, '2TB NVMe',        '2026-01-02');
INSERT INTO reservation_resource VALUES (6,  3,  4,  '16 vCPU / 128GB', '2026-01-07');
INSERT INTO reservation_resource VALUES (7,  3,  5,  '16 vCPU / 128GB', '2026-01-07');
INSERT INTO reservation_resource VALUES (8,  3,  9,  '5TB SSD',         '2026-01-07');
INSERT INTO reservation_resource VALUES (9,  4,  19, '8 vCPU / 32GB',   '2026-01-12');
INSERT INTO reservation_resource VALUES (10, 4,  20, '8 vCPU / 32GB',   '2026-01-12');
INSERT INTO reservation_resource VALUES (11, 4,  25, 'L4 balancer',     '2026-01-12');
INSERT INTO reservation_resource VALUES (12, 5,  34, '4x A100 GPU',     '2026-01-12');
INSERT INTO reservation_resource VALUES (13, 5,  33, '16 vCPU / 128GB', '2026-01-12');
INSERT INTO reservation_resource VALUES (14, 6,  31, '4 vCPU / 16GB',   '2026-01-18');
INSERT INTO reservation_resource VALUES (15, 6,  32, '8 vCPU / 32GB',   '2026-01-18');
INSERT INTO reservation_resource VALUES (16, 7,  28, '8 vCPU / 32GB',   '2026-01-22');
INSERT INTO reservation_resource VALUES (17, 7,  23, '5TB SSD',         '2026-01-22');
INSERT INTO reservation_resource VALUES (18, 8,  22, '8x A100 GPU',     '2026-01-28');
INSERT INTO reservation_resource VALUES (19, 9,  13, '8 vCPU / 32GB',   '2026-01-28');
INSERT INTO reservation_resource VALUES (20, 10, 7,  '4x A100 GPU',     '2026-02-03');
INSERT INTO reservation_resource VALUES (21, 11, 14, '4 vCPU / 16GB',   '2026-02-08');
INSERT INTO reservation_resource VALUES (22, 11, 2,  '4 vCPU / 16GB',   '2026-02-08');
INSERT INTO reservation_resource VALUES (23, 12, 16, '10TB SSD',        '2026-02-12');
INSERT INTO reservation_resource VALUES (24, 12, 41, '8 vCPU / 32GB',   '2026-02-12');
INSERT INTO reservation_resource VALUES (25, 13, 18, '2TB NVMe',        '2026-02-18');
INSERT INTO reservation_resource VALUES (26, 14, 3,  '8 vCPU / 32GB',   '2026-02-22');
INSERT INTO reservation_resource VALUES (27, 15, 13, '8 vCPU / 32GB',   '2026-02-26');
INSERT INTO reservation_resource VALUES (28, 16, 20, '8 vCPU / 32GB',   '2026-02-26');
INSERT INTO reservation_resource VALUES (29, 17, 35, '5TB SSD',         '2026-03-02');
INSERT INTO reservation_resource VALUES (30, 18, 38, 'L7 balancer',     '2026-03-08');
INSERT INTO reservation_resource VALUES (31, 19, 42, '5TB SSD',         '2026-03-12');
INSERT INTO reservation_resource VALUES (32, 20, 40, '16 vCPU / 128GB', '2026-03-18');

-- Deployments Data (25 deployments)

INSERT INTO deployment VALUES (1,  1,  1,    'meridian-pipeline-prod',    'active',     'high',     '2026-01-01', NULL,          1);
INSERT INTO deployment VALUES (2,  2,  2,    'meridian-fraud-training',   'active',     'high',     '2026-01-05', NULL,          0);
INSERT INTO deployment VALUES (3,  3,  3,    'qhealth-ehr-migration',    'active',     'critical', '2026-01-10', NULL,          0);
INSERT INTO deployment VALUES (4,  4,  4,    'novacraft-season4-servers', 'terminated', 'high',     '2026-01-15', '2026-02-28', 1);
INSERT INTO deployment VALUES (5,  5,  5,    'terraform-genome-v2',       'active',     'standard', '2026-01-15', NULL,          0);
INSERT INTO deployment VALUES (6,  6,  6,    'pinnacle-4k-stream',        'active',     'high',     '2026-01-20', NULL,          1);
INSERT INTO deployment VALUES (7,  7,  7,    'greenline-route-engine',    'active',     'standard', '2026-01-25', NULL,          0);
INSERT INTO deployment VALUES (8,  8,  8,    'terraform-arctic-sim',      'active',     'standard', '2026-02-01', NULL,          0);
INSERT INTO deployment VALUES (9,  9,  9,    'zoe-indie-backend',         'terminated', 'standard', '2026-02-01', '2026-02-28', 1);
INSERT INTO deployment VALUES (10, 10, 10,   'lucas-nlp-finetune',        'terminated', 'standard', '2026-02-05', '2026-03-15', 0);
INSERT INTO deployment VALUES (11, 11, 11,   'pinnacle-ads-v3',           'active',     'high',     '2026-02-10', NULL,          1);
INSERT INTO deployment VALUES (12, 12, 12,   'greenline-warehouse',       'active',     'standard', '2026-02-15', NULL,          0);
INSERT INTO deployment VALUES (13, 13, 3,    'qhealth-compliance-scan',   'active',     'critical', '2026-02-20', NULL,          0);
INSERT INTO deployment VALUES (14, 14, NULL, 'novacraft-qa-batch',        'terminated', 'standard', '2026-02-25', '2026-03-15', 0);
INSERT INTO deployment VALUES (15, 15, 1,    'meridian-pipeline-staging', 'active',     'standard', '2026-03-01', NULL,          0);
INSERT INTO deployment VALUES (16, 16, 4,    'novacraft-season4-hotfix',  'active',     'standard', '2026-03-01', NULL,          0);
INSERT INTO deployment VALUES (17, 17, 5,    'terraform-genome-external', 'active',     'standard', '2026-03-05', NULL,          0);
INSERT INTO deployment VALUES (18, 18, 6,    'pinnacle-live-event',       'active',     'high',     '2026-03-10', NULL,          1);
INSERT INTO deployment VALUES (19, 19, 12,   'greenline-inventory-sync',  'active',     'standard', '2026-03-15', NULL,          0);
INSERT INTO deployment VALUES (20, 20, 8,    'terraform-arctic-phase2',   'active',     'standard', '2026-03-20', NULL,          0);
-- Second deployments from same reservations (shows 1-to-many)
INSERT INTO deployment VALUES (21, 1,  1,    'meridian-pipeline-backup',  'active',     'standard', '2026-02-01', NULL,          0);
INSERT INTO deployment VALUES (22, 3,  3,    'qhealth-ehr-staging',      'terminated', 'standard', '2026-01-20', '2026-02-15', 0);
INSERT INTO deployment VALUES (23, 4,  4,    'novacraft-loadtest',        'terminated', 'standard', '2026-01-20', '2026-01-25', 0);
INSERT INTO deployment VALUES (24, 6,  6,    'pinnacle-4k-test',          'terminated', 'standard', '2026-01-22', '2026-01-30', 0);
INSERT INTO deployment VALUES (25, 11, 11,   'pinnacle-ads-staging',      'terminated', 'standard', '2026-02-12', '2026-02-20', 0);

-- Deployment resources (what each deployment actually uses)
INSERT INTO deployment_resource VALUES (1,  1,  1,  '2026-01-01', NULL,          NULL);
INSERT INTO deployment_resource VALUES (2,  1,  8,  '2026-01-01', NULL,          NULL);
INSERT INTO deployment_resource VALUES (3,  1,  11, '2026-01-01', NULL,          NULL);
INSERT INTO deployment_resource VALUES (4,  2,  6,  '2026-01-05', NULL,          NULL);
INSERT INTO deployment_resource VALUES (5,  2,  10, '2026-01-05', NULL,          NULL);
INSERT INTO deployment_resource VALUES (6,  3,  4,  '2026-01-10', NULL,          NULL);
INSERT INTO deployment_resource VALUES (7,  3,  5,  '2026-01-10', NULL,          NULL);
INSERT INTO deployment_resource VALUES (8,  3,  9,  '2026-01-10', NULL,          NULL);
INSERT INTO deployment_resource VALUES (9,  4,  19, '2026-01-15', '2026-02-28', 1056.0);
INSERT INTO deployment_resource VALUES (10, 4,  20, '2026-01-15', '2026-02-28', 1056.0);
INSERT INTO deployment_resource VALUES (11, 4,  25, '2026-01-15', '2026-02-28', 1056.0);
INSERT INTO deployment_resource VALUES (12, 5,  34, '2026-01-15', NULL,          NULL);
INSERT INTO deployment_resource VALUES (13, 5,  33, '2026-01-15', NULL,          NULL);
INSERT INTO deployment_resource VALUES (14, 6,  31, '2026-01-20', NULL,          NULL);
INSERT INTO deployment_resource VALUES (15, 6,  32, '2026-01-20', NULL,          NULL);
INSERT INTO deployment_resource VALUES (16, 7,  28, '2026-01-25', NULL,          NULL);
INSERT INTO deployment_resource VALUES (17, 7,  23, '2026-01-25', NULL,          NULL);
INSERT INTO deployment_resource VALUES (18, 8,  22, '2026-02-01', NULL,          NULL);
INSERT INTO deployment_resource VALUES (19, 9,  13, '2026-02-01', '2026-02-28', 648.0);
INSERT INTO deployment_resource VALUES (20, 10, 7,  '2026-02-05', '2026-03-15', 912.0);
INSERT INTO deployment_resource VALUES (21, 11, 14, '2026-02-10', NULL,          NULL);
INSERT INTO deployment_resource VALUES (22, 11, 2,  '2026-02-10', NULL,          NULL);
INSERT INTO deployment_resource VALUES (23, 12, 16, '2026-02-15', NULL,          NULL);
INSERT INTO deployment_resource VALUES (24, 12, 41, '2026-02-15', NULL,          NULL);
INSERT INTO deployment_resource VALUES (25, 13, 18, '2026-02-20', NULL,          NULL);
INSERT INTO deployment_resource VALUES (26, 14, 3,  '2026-02-25', '2026-03-15', 432.0);
INSERT INTO deployment_resource VALUES (27, 15, 13, '2026-03-01', NULL,          NULL);
INSERT INTO deployment_resource VALUES (28, 16, 20, '2026-03-01', NULL,          NULL);
INSERT INTO deployment_resource VALUES (29, 17, 35, '2026-03-05', NULL,          NULL);
INSERT INTO deployment_resource VALUES (30, 18, 38, '2026-03-10', NULL,          NULL);
INSERT INTO deployment_resource VALUES (31, 19, 42, '2026-03-15', NULL,          NULL);
INSERT INTO deployment_resource VALUES (32, 20, 40, '2026-03-20', NULL,          NULL);
INSERT INTO deployment_resource VALUES (33, 21, 2,  '2026-02-01', NULL,          NULL);
INSERT INTO deployment_resource VALUES (34, 22, 5,  '2026-01-20', '2026-02-15', 624.0);
INSERT INTO deployment_resource VALUES (35, 23, 19, '2026-01-20', '2026-01-25', 120.0);
INSERT INTO deployment_resource VALUES (36, 24, 32, '2026-01-22', '2026-01-30', 192.0);
INSERT INTO deployment_resource VALUES (37, 25, 14, '2026-02-12', '2026-02-20', 192.0);
-- Scaling: deployment 4 scaled up mid-run, added resource
INSERT INTO deployment_resource VALUES (38, 4,  26, '2026-02-01', '2026-02-28', 648.0);

-- Scaling Events

INSERT INTO scaling_event VALUES (1,  1,  NULL, 'scale-up',   2, 3,  '2026-01-15 08:30:00');
INSERT INTO scaling_event VALUES (2,  4,  NULL, 'scale-up',   2, 3,  '2026-02-01 14:00:00');
INSERT INTO scaling_event VALUES (3,  4,  5,    'scale-down', 3, 2,  '2026-02-20 10:00:00');
INSERT INTO scaling_event VALUES (4,  6,  NULL, 'scale-up',   2, 4,  '2026-02-14 20:15:00');
INSERT INTO scaling_event VALUES (5,  9,  NULL, 'scale-up',   1, 2,  '2026-02-10 11:00:00');
INSERT INTO scaling_event VALUES (6,  9,  NULL, 'scale-down', 2, 1,  '2026-02-22 09:00:00');
INSERT INTO scaling_event VALUES (7,  11, NULL, 'scale-up',   2, 3,  '2026-02-28 16:45:00');
INSERT INTO scaling_event VALUES (8,  1,  NULL, 'scale-up',   3, 4,  '2026-03-05 07:20:00');
INSERT INTO scaling_event VALUES (9,  18, NULL, 'scale-up',   1, 3,  '2026-03-12 19:30:00');
INSERT INTO scaling_event VALUES (10, 11, 5,    'scale-down', 3, 2,  '2026-03-20 12:00:00');

-- Deployment Events

INSERT INTO deployment_event VALUES (1,  3,  1,    'migrated',   '2026-01-25 03:00:00', 'Migrated from resource 4 failover to resource 5');
INSERT INTO deployment_event VALUES (2,  4,  NULL,  'paused',     '2026-02-10 02:00:00', 'Scheduled maintenance window');
INSERT INTO deployment_event VALUES (3,  4,  NULL,  'resumed',    '2026-02-10 06:00:00', 'Maintenance complete');
INSERT INTO deployment_event VALUES (4,  4,  5,     'terminated', '2026-02-28 23:59:00', 'Season 4 launch period ended');
INSERT INTO deployment_event VALUES (5,  9,  NULL,  'paused',     '2026-02-15 04:00:00', 'Client requested pause to save costs');
INSERT INTO deployment_event VALUES (6,  9,  NULL,  'resumed',    '2026-02-18 10:00:00', 'Client resumed for weekend testing');
INSERT INTO deployment_event VALUES (7,  9,  NULL,  'terminated', '2026-02-28 18:00:00', 'Project completed');
INSERT INTO deployment_event VALUES (8,  10, NULL,  'terminated', '2026-03-15 12:00:00', 'NLP experiments concluded');
INSERT INTO deployment_event VALUES (9,  14, NULL,  'terminated', '2026-03-15 09:00:00', 'QA batch processing complete');
INSERT INTO deployment_event VALUES (10, 22, 4,     'terminated', '2026-02-15 14:00:00', 'Staging no longer needed');
INSERT INTO deployment_event VALUES (11, 23, NULL,  'terminated', '2026-01-25 22:00:00', 'Load test finished');
INSERT INTO deployment_event VALUES (12, 24, NULL,  'terminated', '2026-01-30 16:00:00', 'Test stream concluded');
INSERT INTO deployment_event VALUES (13, 25, NULL,  'terminated', '2026-02-20 11:00:00', 'Ads staging merged to prod');
INSERT INTO deployment_event VALUES (14, 6,  2,     'migrated',   '2026-03-01 04:00:00', 'Migrated to upgraded node for 4K bandwidth');

-- Billing Data

-- Billing accounts (org accounts + 2 individual accounts)
INSERT INTO billing_account VALUES (1,  1,    NULL, 'Meridian Primary',       'invoice',     50000,  'active');
INSERT INTO billing_account VALUES (2,  2,    NULL, 'Quantum Health Main',    'invoice',     100000, 'active');
INSERT INTO billing_account VALUES (3,  3,    NULL, 'NovaCraft Gaming',       'credit_card', 20000,  'active');
INSERT INTO billing_account VALUES (4,  4,    NULL, 'Terraform Labs Grant',   'purchase_order', 30000, 'active');
INSERT INTO billing_account VALUES (5,  5,    NULL, 'Pinnacle Media Ops',     'invoice',     40000,  'active');
INSERT INTO billing_account VALUES (6,  6,    NULL, 'Greenline Cloud',        'invoice',     25000,  'active');
INSERT INTO billing_account VALUES (7,  NULL, 16,   'Zoe Fischer Personal',   'credit_card', 2000,   'active');
INSERT INTO billing_account VALUES (8,  NULL, 17,   'Lucas Duarte Personal',  'credit_card', 5000,   'active');

-- Cost centers
INSERT INTO cost_center VALUES (1,  1, 'Meridian Engineering',  30000);
INSERT INTO cost_center VALUES (2,  1, 'Meridian Research',     20000);
INSERT INTO cost_center VALUES (3,  2, 'QH Clinical Systems',   60000);
INSERT INTO cost_center VALUES (4,  2, 'QH Compliance',         40000);
INSERT INTO cost_center VALUES (5,  3, 'NovaCraft Production',  15000);
INSERT INTO cost_center VALUES (6,  3, 'NovaCraft QA',          5000);
INSERT INTO cost_center VALUES (7,  4, 'TF Genomics',           20000);
INSERT INTO cost_center VALUES (8,  4, 'TF Climate',            10000);
INSERT INTO cost_center VALUES (9,  5, 'Pinnacle Streaming',    25000);
INSERT INTO cost_center VALUES (10, 5, 'Pinnacle Advertising',  15000);
INSERT INTO cost_center VALUES (11, 6, 'GL Routing',            15000);
INSERT INTO cost_center VALUES (12, 6, 'GL Warehouse',          10000);

-- 6 service types
INSERT INTO service_type VALUES (1, 'Compute Hours',    'compute',  'hours',     0.50);
INSERT INTO service_type VALUES (2, 'GPU Hours',        'compute',  'hours',     3.50);
INSERT INTO service_type VALUES (3, 'Storage',          'storage',  'GB-month',  0.10);
INSERT INTO service_type VALUES (4, 'Network Transfer', 'network',  'GB',        0.08);
INSERT INTO service_type VALUES (5, 'Premium Support',  'support',  'month',     500.00);
INSERT INTO service_type VALUES (6, 'Backup',           'storage',  'GB-month',  0.05);

-- Invoices (monthly for Q1, per billing account)
-- January invoices
INSERT INTO invoice VALUES (1,  1, '2026-01-01', '2026-01-31', 4280.00, 'paid',    '2026-02-01', '2026-02-28');
INSERT INTO invoice VALUES (2,  2, '2026-01-01', '2026-01-31', 5640.00, 'paid',    '2026-02-01', '2026-02-28');
INSERT INTO invoice VALUES (3,  3, '2026-01-01', '2026-01-31', 1920.00, 'paid',    '2026-02-01', '2026-02-28');
INSERT INTO invoice VALUES (4,  4, '2026-01-01', '2026-01-31', 6580.00, 'paid',    '2026-02-01', '2026-02-28');
INSERT INTO invoice VALUES (5,  5, '2026-01-01', '2026-01-31', 1440.00, 'paid',    '2026-02-01', '2026-02-28');
-- February invoices
INSERT INTO invoice VALUES (6,  1, '2026-02-01', '2026-02-28', 4850.00, 'paid',    '2026-03-01', '2026-03-28');
INSERT INTO invoice VALUES (7,  2, '2026-02-01', '2026-02-28', 6120.00, 'paid',    '2026-03-01', '2026-03-28');
INSERT INTO invoice VALUES (8,  3, '2026-02-01', '2026-02-28', 2340.00, 'paid',    '2026-03-01', '2026-03-28');
INSERT INTO invoice VALUES (9,  4, '2026-02-01', '2026-02-28', 7200.00, 'paid',    '2026-03-01', '2026-03-28');
INSERT INTO invoice VALUES (10, 5, '2026-02-01', '2026-02-28', 2860.00, 'paid',    '2026-03-01', '2026-03-28');
INSERT INTO invoice VALUES (11, 6, '2026-02-01', '2026-02-28', 1680.00, 'paid',    '2026-03-01', '2026-03-28');
INSERT INTO invoice VALUES (12, 7, '2026-02-01', '2026-02-28', 860.00,  'paid',    '2026-03-01', '2026-03-28');
INSERT INTO invoice VALUES (13, 8, '2026-02-01', '2026-02-28', 3920.00, 'paid',    '2026-03-01', '2026-03-28');
-- March invoices (still pending)
INSERT INTO invoice VALUES (14, 1, '2026-03-01', '2026-03-31', 5200.00, 'pending', '2026-04-01', '2026-04-28');
INSERT INTO invoice VALUES (15, 2, '2026-03-01', '2026-03-31', 5880.00, 'pending', '2026-04-01', '2026-04-28');
INSERT INTO invoice VALUES (16, 3, '2026-03-01', '2026-03-31', 1560.00, 'pending', '2026-04-01', '2026-04-28');
INSERT INTO invoice VALUES (17, 4, '2026-03-01', '2026-03-31', 6900.00, 'pending', '2026-04-01', '2026-04-28');
INSERT INTO invoice VALUES (18, 5, '2026-03-01', '2026-03-31', 3640.00, 'pending', '2026-04-01', '2026-04-28');
INSERT INTO invoice VALUES (19, 6, '2026-03-01', '2026-03-31', 2100.00, 'pending', '2026-04-01', '2026-04-28');

-- Charges (120+ entries across Q1)
-- Monthly charges per deployment per service type

-- January Charges
-- Dep 1: Meridian pipeline (compute + storage + network)
INSERT INTO charge VALUES (1,  1, 1, 1,  1,  2160.00, 'finalized', 0, '2026-01-31');
INSERT INTO charge VALUES (2,  3, 1, 1,  1,  500.00,  'finalized', 0, '2026-01-31');
INSERT INTO charge VALUES (3,  4, 1, 1,  1,  620.00,  'finalized', 0, '2026-01-31');
INSERT INTO charge VALUES (4,  5, 1, 1,  1,  500.00,  'finalized', 0, '2026-01-31');
INSERT INTO charge VALUES (5,  6, 1, 1,  1,  500.00,  'finalized', 0, '2026-01-31');
-- Dep 2: Meridian fraud (GPU + storage)
INSERT INTO charge VALUES (6,  2, 1, 2,  1,  2604.00, 'finalized', 0, '2026-01-31');
INSERT INTO charge VALUES (7,  5, 1, 2,  1,  175.00,  'finalized', 0, '2026-01-31');
-- Dep 3: QHealth EHR (compute + storage)
INSERT INTO charge VALUES (8,  1, 2, 3,  2,  3360.00, 'finalized', 0, '2026-01-31');
INSERT INTO charge VALUES (9,  3, 2, 3,  2,  500.00,  'finalized', 0, '2026-01-31');
INSERT INTO charge VALUES (10, 5, 2, 3,  2,  500.00,  'finalized', 0, '2026-01-31');
INSERT INTO charge VALUES (11, 4, 2, 3,  2,  780.00,  'finalized', 0, '2026-01-31');
INSERT INTO charge VALUES (12, 6, 2, 3,  2,  500.00,  'finalized', 0, '2026-01-31');
-- Dep 4: NovaCraft season 4 (compute + network)
INSERT INTO charge VALUES (13, 1, 3, 4,  3,  744.00,  'finalized', 0, '2026-01-31');
INSERT INTO charge VALUES (14, 4, 3, 4,  3,  480.00,  'finalized', 0, '2026-01-31');
INSERT INTO charge VALUES (15, 6, 3, 4,  3,  250.00,  'finalized', 0, '2026-01-31');
-- Dep 22: QHealth staging
INSERT INTO charge VALUES (16, 1, 2, 22, 2,  480.00,  'finalized', 0, '2026-01-31');
-- Dep 23: NovaCraft loadtest
INSERT INTO charge VALUES (17, 1, 3, 23, 3,  60.00,   'finalized', 0, '2026-01-31');
-- Dep 24: Pinnacle 4k test
INSERT INTO charge VALUES (18, 1, 5, 24, 5,  96.00,   'finalized', 0, '2026-01-31');
-- Dep 5: Terraform genome (GPU + compute)
INSERT INTO charge VALUES (19, 2, 4, 5,  4,  2604.00, 'finalized', 0, '2026-01-31');
INSERT INTO charge VALUES (20, 1, 4, 5,  4,  960.00,  'finalized', 0, '2026-01-31');
INSERT INTO charge VALUES (21, 5, 4, 5,  4,  500.00,  'finalized', 0, '2026-01-31');
-- Dep 6: Pinnacle 4K stream (compute)
INSERT INTO charge VALUES (22, 1, 5, 6,  5,  528.00,  'finalized', 0, '2026-01-31');
INSERT INTO charge VALUES (23, 4, 5, 6,  5,  412.00,  'finalized', 0, '2026-01-31');
INSERT INTO charge VALUES (24, 5, 5, 6,  5,  500.00,  'finalized', 0, '2026-01-31');

-- FEBRUARY CHARGES
-- Dep 1: Meridian pipeline
INSERT INTO charge VALUES (25, 1, 1, 1,  6,  2400.00, 'finalized', 0, '2026-02-28');
INSERT INTO charge VALUES (26, 3, 1, 1,  6,  500.00,  'finalized', 0, '2026-02-28');
INSERT INTO charge VALUES (27, 4, 1, 1,  6,  720.00,  'finalized', 0, '2026-02-28');
INSERT INTO charge VALUES (28, 5, 1, 1,  6,  500.00,  'finalized', 0, '2026-02-28');
INSERT INTO charge VALUES (29, 6, 1, 1,  6,  500.00,  'finalized', 0, '2026-02-28');
-- Dep 21: Meridian pipeline backup
INSERT INTO charge VALUES (30, 1, 1, 21, 6,  230.00,  'finalized', 0, '2026-02-28');
-- Dep 2: Meridian fraud
INSERT INTO charge VALUES (31, 2, 1, 2,  6,  2352.00, 'finalized', 0, '2026-02-28');
INSERT INTO charge VALUES (32, 5, 1, 2,  6,  175.00,  'finalized', 0, '2026-02-28');
-- Dep 3: QHealth EHR
INSERT INTO charge VALUES (33, 1, 2, 3,  7,  3360.00, 'finalized', 0, '2026-02-28');
INSERT INTO charge VALUES (34, 3, 2, 3,  7,  500.00,  'finalized', 0, '2026-02-28');
INSERT INTO charge VALUES (35, 5, 2, 3,  7,  500.00,  'finalized', 0, '2026-02-28');
INSERT INTO charge VALUES (36, 4, 2, 3,  7,  860.00,  'finalized', 0, '2026-02-28');
INSERT INTO charge VALUES (37, 6, 2, 3,  7,  500.00,  'finalized', 0, '2026-02-28');
-- Dep 13: QHealth compliance
INSERT INTO charge VALUES (38, 5, 2, 13, 7,  400.00,  'finalized', 0, '2026-02-28');
-- Dep 4: NovaCraft season 4
INSERT INTO charge VALUES (39, 1, 3, 4,  8,  1344.00, 'finalized', 0, '2026-02-28');
INSERT INTO charge VALUES (40, 4, 3, 4,  8,  640.00,  'finalized', 0, '2026-02-28');
INSERT INTO charge VALUES (41, 6, 3, 4,  8,  250.00,  'finalized', 0, '2026-02-28');
-- Dep 14: NovaCraft QA batch
INSERT INTO charge VALUES (42, 1, 3, 14, 8,  106.00,  'finalized', 0, '2026-02-28');
-- Dep 5: Terraform genome
INSERT INTO charge VALUES (43, 2, 4, 5,  9,  2352.00, 'finalized', 0, '2026-02-28');
INSERT INTO charge VALUES (44, 1, 4, 5,  9,  960.00,  'finalized', 0, '2026-02-28');
INSERT INTO charge VALUES (45, 5, 4, 5,  9,  500.00,  'finalized', 0, '2026-02-28');
-- Dep 8: Terraform arctic sim
INSERT INTO charge VALUES (46, 2, 4, 8,  9,  2352.00, 'finalized', 0, '2026-02-28');
INSERT INTO charge VALUES (47, 5, 4, 8,  9,  500.00,  'finalized', 0, '2026-02-28');
-- Dep 6: Pinnacle 4K stream
INSERT INTO charge VALUES (48, 1, 5, 6,  10, 672.00,  'finalized', 0, '2026-02-28');
INSERT INTO charge VALUES (49, 4, 5, 6,  10, 580.00,  'finalized', 0, '2026-02-28');
INSERT INTO charge VALUES (50, 5, 5, 6,  10, 500.00,  'finalized', 0, '2026-02-28');
-- Dep 11: Pinnacle ads v3
INSERT INTO charge VALUES (51, 1, 5, 11, 10, 672.00,  'finalized', 0, '2026-02-28');
INSERT INTO charge VALUES (52, 4, 5, 11, 10, 436.00,  'finalized', 0, '2026-02-28');
-- Dep 25: Pinnacle ads staging
INSERT INTO charge VALUES (53, 1, 5, 25, 10, 96.00,   'finalized', 0, '2026-02-28');
-- Dep 7: Greenline route engine
INSERT INTO charge VALUES (54, 1, 6, 7,  11, 672.00,  'finalized', 0, '2026-02-28');
INSERT INTO charge VALUES (55, 3, 6, 7,  11, 500.00,  'finalized', 0, '2026-02-28');
INSERT INTO charge VALUES (56, 5, 6, 7,  11, 508.00,  'finalized', 0, '2026-02-28');
-- Dep 9: Zoe indie backend
INSERT INTO charge VALUES (57, 1, 7, 9,  12, 648.00,  'finalized', 0, '2026-02-28');
INSERT INTO charge VALUES (58, 4, 7, 9,  12, 212.00,  'finalized', 0, '2026-02-28');
-- Dep 10: Lucas NLP
INSERT INTO charge VALUES (59, 2, 8, 10, 13, 2940.00, 'finalized', 0, '2026-02-28');
INSERT INTO charge VALUES (60, 5, 8, 10, 13, 500.00,  'finalized', 0, '2026-02-28');
INSERT INTO charge VALUES (61, 6, 8, 10, 13, 480.00,  'finalized', 0, '2026-02-28');
-- Dep 12: Greenline warehouse
INSERT INTO charge VALUES (62, 1, 6, 12, 11, 288.00,  'finalized', 0, '2026-02-28');
INSERT INTO charge VALUES (63, 3, 6, 12, 11, 100.00,  'finalized', 0, '2026-02-28');

-- MARCH CHARGES
-- Dep 1: Meridian pipeline
INSERT INTO charge VALUES (64, 1, 1, 1,  14, 2640.00, 'finalized', 0, '2026-03-31');
INSERT INTO charge VALUES (65, 3, 1, 1,  14, 500.00,  'finalized', 0, '2026-03-31');
INSERT INTO charge VALUES (66, 4, 1, 1,  14, 810.00,  'finalized', 0, '2026-03-31');
INSERT INTO charge VALUES (67, 5, 1, 1,  14, 500.00,  'finalized', 0, '2026-03-31');
INSERT INTO charge VALUES (68, 6, 1, 1,  14, 500.00,  'finalized', 0, '2026-03-31');
-- Dep 21: Meridian backup
INSERT INTO charge VALUES (69, 1, 1, 21, 14, 250.00,  'finalized', 0, '2026-03-31');
-- Dep 2: Meridian fraud
INSERT INTO charge VALUES (70, 2, 1, 2,  14, 2604.00, 'finalized', 0, '2026-03-31');
INSERT INTO charge VALUES (71, 5, 1, 2,  14, 175.00,  'finalized', 0, '2026-03-31');
-- Dep 3: QHealth EHR
INSERT INTO charge VALUES (72, 1, 2, 3,  15, 3360.00, 'finalized', 0, '2026-03-31');
INSERT INTO charge VALUES (73, 3, 2, 3,  15, 500.00,  'finalized', 0, '2026-03-31');
INSERT INTO charge VALUES (74, 5, 2, 3,  15, 500.00,  'finalized', 0, '2026-03-31');
INSERT INTO charge VALUES (75, 4, 2, 3,  15, 920.00,  'finalized', 0, '2026-03-31');
INSERT INTO charge VALUES (76, 6, 2, 3,  15, 500.00,  'finalized', 0, '2026-03-31');
-- Dep 13: QHealth compliance
INSERT INTO charge VALUES (77, 5, 2, 13, 15, 500.00,  'finalized', 0, '2026-03-31');
-- Dep 5: Terraform genome
INSERT INTO charge VALUES (78, 2, 4, 5,  17, 2604.00, 'finalized', 0, '2026-03-31');
INSERT INTO charge VALUES (79, 1, 4, 5,  17, 960.00,  'finalized', 0, '2026-03-31');
INSERT INTO charge VALUES (80, 5, 4, 5,  17, 500.00,  'finalized', 0, '2026-03-31');
-- Dep 8: Terraform arctic
INSERT INTO charge VALUES (81, 2, 4, 8,  17, 2604.00, 'finalized', 0, '2026-03-31');
INSERT INTO charge VALUES (82, 5, 4, 8,  17, 500.00,  'finalized', 0, '2026-03-31');
-- Dep 20: Terraform arctic phase 2
INSERT INTO charge VALUES (83, 1, 4, 20, 17, 232.00,  'finalized', 0, '2026-03-31');
-- Dep 17: Terraform genome external
INSERT INTO charge VALUES (84, 3, 4, 17, 17, 260.00,  'finalized', 0, '2026-03-31');
-- Dep 6: Pinnacle 4K stream
INSERT INTO charge VALUES (85, 1, 5, 6,  18, 744.00,  'finalized', 0, '2026-03-31');
INSERT INTO charge VALUES (86, 4, 5, 6,  18, 640.00,  'finalized', 0, '2026-03-31');
INSERT INTO charge VALUES (87, 5, 5, 6,  18, 500.00,  'finalized', 0, '2026-03-31');
-- Dep 11: Pinnacle ads v3
INSERT INTO charge VALUES (88, 1, 5, 11, 18, 744.00,  'finalized', 0, '2026-03-31');
INSERT INTO charge VALUES (89, 4, 5, 11, 18, 512.00,  'finalized', 0, '2026-03-31');
-- Dep 18: Pinnacle live event
INSERT INTO charge VALUES (90, 1, 5, 18, 18, 248.00,  'finalized', 0, '2026-03-31');
INSERT INTO charge VALUES (91, 4, 5, 18, 18, 252.00,  'finalized', 0, '2026-03-31');
-- Dep 7: Greenline route engine
INSERT INTO charge VALUES (92, 1, 6, 7,  19, 744.00,  'finalized', 0, '2026-03-31');
INSERT INTO charge VALUES (93, 3, 6, 7,  19, 500.00,  'finalized', 0, '2026-03-31');
INSERT INTO charge VALUES (94, 5, 6, 7,  19, 500.00,  'finalized', 0, '2026-03-31');
-- Dep 12: Greenline warehouse
INSERT INTO charge VALUES (95, 1, 6, 12, 19, 356.00,  'finalized', 0, '2026-03-31');
INSERT INTO charge VALUES (96, 3, 6, 12, 19, 100.00,  'finalized', 0, '2026-03-31');
-- Dep 19: Greenline inventory sync
INSERT INTO charge VALUES (97, 3, 6, 19, 19, 80.00,   'finalized', 0, '2026-03-31');
-- Dep 10: Lucas NLP (partial March)
INSERT INTO charge VALUES (98, 2, 8, 10, NULL, 1764.00,'finalized', 0, '2026-03-15');
INSERT INTO charge VALUES (99, 5, 8, 10, NULL, 250.00, 'finalized', 0, '2026-03-15');
-- Dep 15: Meridian pipeline staging
INSERT INTO charge VALUES (100, 1, 1, 15, 14, 372.00, 'finalized', 0, '2026-03-31');
-- Dep 16: NovaCraft hotfix
INSERT INTO charge VALUES (101, 1, 3, 16, 16, 372.00, 'finalized', 0, '2026-03-31');
INSERT INTO charge VALUES (102, 4, 3, 16, 16, 288.00, 'finalized', 0, '2026-03-31');
-- Provisional charges (active deployments, current period)
INSERT INTO charge VALUES (103, 1, 1, 1,  NULL, 900.00, 'provisional', 1, '2026-03-31');
INSERT INTO charge VALUES (104, 2, 1, 2,  NULL, 1200.00,'provisional', 1, '2026-03-31');

-- Charge Allocations (split billing examples)

-- Meridian: pipeline charges split 70% Engineering / 30% Research
INSERT INTO charge_allocation VALUES (1,  1,  1, 70.0, 1512.00);
INSERT INTO charge_allocation VALUES (2,  1,  2, 30.0, 648.00);
INSERT INTO charge_allocation VALUES (3,  25, 1, 70.0, 1680.00);
INSERT INTO charge_allocation VALUES (4,  25, 2, 30.0, 720.00);
INSERT INTO charge_allocation VALUES (5,  64, 1, 70.0, 1848.00);
INSERT INTO charge_allocation VALUES (6,  64, 2, 30.0, 792.00);

-- QHealth: EHR charges split 60% Clinical / 40% Compliance
INSERT INTO charge_allocation VALUES (7,  8,  3, 60.0, 2016.00);
INSERT INTO charge_allocation VALUES (8,  8,  4, 40.0, 1344.00);
INSERT INTO charge_allocation VALUES (9,  33, 3, 60.0, 2016.00);
INSERT INTO charge_allocation VALUES (10, 33, 4, 40.0, 1344.00);
INSERT INTO charge_allocation VALUES (11, 72, 3, 60.0, 2016.00);
INSERT INTO charge_allocation VALUES (12, 72, 4, 40.0, 1344.00);

-- NovaCraft: season 4 charges split 80% Production / 20% QA
INSERT INTO charge_allocation VALUES (13, 13, 5, 80.0, 595.20);
INSERT INTO charge_allocation VALUES (14, 13, 6, 20.0, 148.80);
INSERT INTO charge_allocation VALUES (15, 39, 5, 80.0, 1075.20);
INSERT INTO charge_allocation VALUES (16, 39, 6, 20.0, 268.80);

-- Pinnacle: streaming charges split 65% Streaming / 35% Advertising
INSERT INTO charge_allocation VALUES (17, 22, 9,  65.0, 343.20);
INSERT INTO charge_allocation VALUES (18, 22, 10, 35.0, 184.80);
INSERT INTO charge_allocation VALUES (19, 48, 9,  65.0, 436.80);
INSERT INTO charge_allocation VALUES (20, 48, 10, 35.0, 235.20);

-- Adjustments (8 entries across Q1 for credits/surcharges)

INSERT INTO adjustment VALUES (1,  8,  3, 'credit',    -280.00, 'Resource 4 failover caused 4hr downtime during EHR migration', '2026-01-26');
INSERT INTO adjustment VALUES (2,  6,  3, 'credit',    -175.00, 'GPU cooling failure caused 6hr training interruption',          '2026-02-11');
INSERT INTO adjustment VALUES (3,  39, 3, 'surcharge',  200.00, 'Emergency scale-up during Season 4 peak',                      '2026-02-05');
INSERT INTO adjustment VALUES (4,  46, 3, 'credit',    -120.00, 'GPU maintenance overrun delayed arctic simulation by 2hrs',     '2026-02-03');
INSERT INTO adjustment VALUES (5,  57, 3, 'credit',    -50.00,  'Network latency spike during indie backend testing',            '2026-02-20');
INSERT INTO adjustment VALUES (6,  85, 3, 'surcharge',  150.00, 'After-hours support for live 4K event setup',                   '2026-03-11');
INSERT INTO adjustment VALUES (7,  72, 3, 'credit',    -200.00, 'Scheduled maintenance overlapped with EHR migration window',    '2026-03-16');
INSERT INTO adjustment VALUES (8,  92, 3, 'surcharge',  100.00, 'Expedited provisioning for route engine expansion',             '2026-03-22');

-- Access & Security Data

-- Credentials (1-3 per active client)
INSERT INTO credential VALUES (1,  1,  'api_key',     1, '2025-11-01', '2026-11-01');
INSERT INTO credential VALUES (2,  1,  'password',    1, '2024-06-01', NULL);
INSERT INTO credential VALUES (3,  2,  'api_key',     1, '2025-11-15', '2026-11-15');
INSERT INTO credential VALUES (4,  2,  'certificate', 1, '2026-01-01', '2027-01-01');
INSERT INTO credential VALUES (5,  3,  'api_key',     1, '2025-12-01', '2026-12-01');
INSERT INTO credential VALUES (6,  3,  'password',    1, '2024-07-15', NULL);
INSERT INTO credential VALUES (7,  5,  'api_key',     1, '2025-12-15', '2026-12-15');
INSERT INTO credential VALUES (8,  5,  'token',       1, '2026-01-10', '2026-07-10');
INSERT INTO credential VALUES (9,  7,  'api_key',     1, '2025-12-20', '2026-12-20');
INSERT INTO credential VALUES (10, 7,  'password',    1, '2025-01-10', NULL);
INSERT INTO credential VALUES (11, 9,  'api_key',     1, '2026-01-05', '2027-01-05');
INSERT INTO credential VALUES (12, 11, 'api_key',     1, '2026-01-10', '2027-01-10');
INSERT INTO credential VALUES (13, 16, 'password',    1, '2025-07-01', NULL);
INSERT INTO credential VALUES (14, 16, 'api_key',     1, '2026-01-20', '2027-01-20');
INSERT INTO credential VALUES (15, 17, 'api_key',     1, '2026-02-01', '2027-02-01');
INSERT INTO credential VALUES (16, 8,  'api_key',     1, '2026-01-15', '2027-01-15');
INSERT INTO credential VALUES (17, 10, 'api_key',     1, '2026-02-10', '2027-02-10');
INSERT INTO credential VALUES (18, 12, 'api_key',     1, '2026-02-15', '2027-02-15');
INSERT INTO credential VALUES (19, 4,  'certificate', 1, '2026-02-18', '2027-02-18');
INSERT INTO credential VALUES (20, 19, 'api_key',     1, '2026-03-10', '2027-03-10');

-- Access logs (30 entries across Q1)
INSERT INTO accessLog VALUES (1,  1,  1,  1,    1,  'deploy',    '10.0.1.50',     '2026-01-01 00:15:00');
INSERT INTO accessLog VALUES (2,  1,  8,  1,    1,  'deploy',    '10.0.1.50',     '2026-01-01 00:16:00');
INSERT INTO accessLog VALUES (3,  2,  6,  2,    3,  'deploy',    '10.0.2.12',     '2026-01-05 09:00:00');
INSERT INTO accessLog VALUES (4,  3,  4,  3,    5,  'deploy',    '172.16.5.22',   '2026-01-10 08:00:00');
INSERT INTO accessLog VALUES (5,  5,  19, 4,    7,  'deploy',    '192.168.1.100', '2026-01-15 14:00:00');
INSERT INTO accessLog VALUES (6,  7,  34, 5,    9,  'deploy',    '10.10.10.5',    '2026-01-15 10:00:00');
INSERT INTO accessLog VALUES (7,  9,  31, 6,    11, 'deploy',    '10.20.0.15',    '2026-01-20 16:00:00');
INSERT INTO accessLog VALUES (8,  11, 28, 7,    12, 'deploy',    '10.30.0.22',    '2026-01-25 11:00:00');
INSERT INTO accessLog VALUES (9,  8,  22, 8,    16, 'deploy',    '10.10.10.8',    '2026-02-01 08:00:00');
INSERT INTO accessLog VALUES (10, 16, 13, 9,    14, 'deploy',    '73.45.128.90',  '2026-02-01 20:00:00');
INSERT INTO accessLog VALUES (11, 17, 7,  10,   15, 'deploy',    '84.12.200.44',  '2026-02-05 15:00:00');
INSERT INTO accessLog VALUES (12, 10, 14, 11,   17, 'deploy',    '10.20.0.30',    '2026-02-10 09:00:00');
INSERT INTO accessLog VALUES (13, 12, 16, 12,   18, 'deploy',    '10.30.0.40',    '2026-02-15 13:00:00');
INSERT INTO accessLog VALUES (14, 4,  18, 13,   19, 'deploy',    '172.16.5.30',   '2026-02-20 10:00:00');
INSERT INTO accessLog VALUES (15, 5,  19, 4,    7,  'modify',    '192.168.1.100', '2026-02-01 14:30:00');
INSERT INTO accessLog VALUES (16, 1,  1,  1,    1,  'modify',    '10.0.1.50',     '2026-02-15 11:00:00');
INSERT INTO accessLog VALUES (17, 16, 13, 9,    14, 'terminate', '73.45.128.90',  '2026-02-28 18:00:00');
INSERT INTO accessLog VALUES (18, 5,  19, 4,    8,  'terminate', '192.168.1.100', '2026-02-28 23:59:00');
INSERT INTO accessLog VALUES (19, 13, 13, 15,   1,  'deploy',    '10.0.1.55',     '2026-03-01 08:00:00');
INSERT INTO accessLog VALUES (20, 14, 20, 16,   7,  'deploy',    '192.168.1.110', '2026-03-01 09:00:00');
INSERT INTO accessLog VALUES (21, 9,  31, 6,    11, 'modify',    '10.20.0.15',    '2026-03-01 04:30:00');
INSERT INTO accessLog VALUES (22, 15, 35, 17,   9,  'deploy',    '10.10.10.15',   '2026-03-05 12:00:00');
INSERT INTO accessLog VALUES (23, 19, 38, 18,   20, 'deploy',    '10.20.0.50',    '2026-03-10 18:00:00');
INSERT INTO accessLog VALUES (24, 20, 42, 19,   18, 'deploy',    '10.30.0.55',    '2026-03-15 10:00:00');
INSERT INTO accessLog VALUES (25, 18, 40, 20,   16, 'deploy',    '10.10.10.18',   '2026-03-20 14:00:00');
INSERT INTO accessLog VALUES (26, 17, 7,  10,   15, 'terminate', '84.12.200.44',  '2026-03-15 12:00:00');
INSERT INTO accessLog VALUES (27, 6,  3,  14,   NULL,'deploy',   '192.168.1.105', '2026-02-25 16:00:00');
INSERT INTO accessLog VALUES (28, 6,  3,  14,   NULL,'terminate','192.168.1.105', '2026-03-15 09:00:00');
INSERT INTO accessLog VALUES (29, 1,  2,  21,   2,  'deploy',    '10.0.1.50',     '2026-02-01 06:00:00');
INSERT INTO accessLog VALUES (30, 10, 2,  11,   17, 'modify',    '10.20.0.30',    '2026-02-28 16:50:00');

-- Part 3: Queries and Interpretation
-- 11 queries that transform raw data into meaningful information


-- ============================================================
-- QUERY 1: What resources are assigned to a deployment?
-- ============================================================
-- WHY THIS IS USEFUL: When a client reports a problem with their
-- deployment, support staff need to immediately see which specific
-- machines are running the workload, what type they are, and where
-- they physically sit. This query gives a complete resource map
-- for any deployment in one view.
-- ============================================================

SELECT
    d.deploymentId,
    d.deploymentName,
    d.status AS deploymentStatus,
    r.resourceId,
    r.serialNumber,
    rt.typeName AS resourceType,
    rt.category,
    dc.name AS dataCenter,
    az.zoneName,
    reg.regionName,
    dr.allocatedAt,
    dr.deallocatedAt,
    dr.usageHours
FROM deployment d
JOIN deployment_resource dr ON d.deploymentId = dr.deploymentId
JOIN resource r ON dr.resourceId = r.resourceId
JOIN resource_type rt ON r.resourceTypeId = rt.resourceTypeId
JOIN data_center dc ON r.datacenterId = dc.datacenterId
JOIN availability_zone az ON dc.zoneId = az.zoneId
JOIN region reg ON az.regionId = reg.regionId
WHERE d.deploymentId = 1
ORDER BY dr.allocatedAt;


-- ============================================================
-- QUERY 2: What usage has occurred over time?
-- ============================================================
-- WHY THIS IS USEFUL: Operations managers need to see whether the
-- platform is getting busier or quieter over time. This query
-- counts how many deployments were active in each month and how
-- many resources were being used, which helps with capacity
-- planning and hiring decisions.
-- ============================================================

SELECT
    strftime('%Y-%m', dr.allocatedAt) AS month,
    COUNT(DISTINCT dr.deploymentId) AS activeDeployments,
    COUNT(DISTINCT dr.resourceId) AS resourcesUsed,
    ROUND(SUM(CASE
        WHEN dr.usageHours IS NOT NULL THEN dr.usageHours
        ELSE ROUND((julianday(COALESCE(dr.deallocatedAt, '2026-03-31')) - julianday(dr.allocatedAt)) * 24, 1)
    END), 1) AS totalUsageHours
FROM deployment_resource dr
GROUP BY strftime('%Y-%m', dr.allocatedAt)
ORDER BY month;


-- ============================================================
-- QUERY 3: What charges were generated for a client or org?
-- ============================================================
-- WHY THIS IS USEFUL: Account managers need a clear breakdown of
-- what a client is being charged for. This query shows every
-- charge grouped by service type for a given organization, so the
-- account manager can explain the bill to the client and identify
-- which services are driving the most cost.
-- ============================================================

SELECT
    o.orgName,
    st.serviceName,
    st.category,
    COUNT(c.chargeId) AS numberOfCharges,
    ROUND(SUM(c.amount), 2) AS totalAmount,
    ROUND(AVG(c.amount), 2) AS avgChargeAmount
FROM charge c
JOIN billing_account ba ON c.billingAccountId = ba.billingAccountId
JOIN organization o ON ba.orgId = o.orgId
JOIN service_type st ON c.serviceTypeId = st.serviceTypeId
GROUP BY o.orgName, st.serviceName
ORDER BY o.orgName, totalAmount DESC;


-- ============================================================
-- QUERY 4: How are charges split across cost centers?
-- ============================================================
-- WHY THIS IS USEFUL: Large organizations split cloud costs across
-- departments. Finance teams need to see how much each department
-- is actually spending so they can track budgets. This query shows
-- each cost center's allocated spend vs. its budget limit, making
-- it easy to spot departments that are close to their cap.
-- ============================================================

SELECT
    o.orgName,
    cc.centerName,
    cc.budgetLimit,
    ROUND(SUM(ca.amount), 2) AS allocatedSpend,
    ROUND(cc.budgetLimit - SUM(ca.amount), 2) AS budgetRemaining,
    ROUND((SUM(ca.amount) / cc.budgetLimit) * 100, 1) AS percentUsed
FROM charge_allocation ca
JOIN cost_center cc ON ca.costCenterId = cc.costCenterId
JOIN billing_account ba ON cc.billingAccountId = ba.billingAccountId
JOIN organization o ON ba.orgId = o.orgId
GROUP BY o.orgName, cc.centerName, cc.budgetLimit
ORDER BY percentUsed DESC;


-- ============================================================
-- QUERY 5: What invoices are outstanding?
-- ============================================================
-- WHY THIS IS USEFUL: The finance team needs to know who owes
-- money and how much. This query shows all unpaid invoices with
-- the associated organization or individual client, sorted by
-- due date so the team can prioritize collection efforts.
-- ============================================================

SELECT
    inv.invoiceId,
    COALESCE(o.orgName, cl.firstName || ' ' || cl.lastName) AS billedTo,
    ba.accountName,
    inv.periodStart,
    inv.periodEnd,
    inv.totalAmount,
    inv.status,
    inv.dueAt,
    ROUND(julianday(inv.dueAt) - julianday('2026-03-31'), 0) AS daysUntilDue
FROM invoice inv
JOIN billing_account ba ON inv.billingAccountId = ba.billingAccountId
LEFT JOIN organization o ON ba.orgId = o.orgId
LEFT JOIN client cl ON ba.clientId = cl.clientId
WHERE inv.status = 'pending'
ORDER BY inv.dueAt;


-- ============================================================
-- QUERY 6: Total revenue by region
-- ============================================================
-- WHY THIS IS USEFUL: Leadership needs to know which geographic
-- regions are generating the most revenue. This helps decide where
-- to invest in new data centers. A region generating lots of
-- revenue with high utilization probably needs expansion. A region
-- with low revenue might need better marketing or pricing changes.
-- This is the longest join chain in the database.
-- We use a CTE to map each deployment to its primary region
-- (the region of the first resource allocated) to avoid
-- double-counting charges when a deployment uses multiple resources.
-- ============================================================
 
WITH deployment_region AS (
    SELECT
        dr.deploymentId,
        reg.regionName,
        ROW_NUMBER() OVER (PARTITION BY dr.deploymentId ORDER BY dr.allocatedAt) AS rn
    FROM deployment_resource dr
    JOIN resource r ON dr.resourceId = r.resourceId
    JOIN data_center dc ON r.datacenterId = dc.datacenterId
    JOIN availability_zone az ON dc.zoneId = az.zoneId
    JOIN region reg ON az.regionId = reg.regionId
)
SELECT
    dreg.regionName,
    COUNT(DISTINCT c.chargeId) AS totalCharges,
    COUNT(DISTINCT d.deploymentId) AS totalDeployments,
    ROUND(SUM(c.amount), 2) AS totalRevenue,
    ROUND(AVG(c.amount), 2) AS avgChargeAmount
FROM charge c
JOIN deployment d ON c.deploymentId = d.deploymentId
JOIN deployment_region dreg ON d.deploymentId = dreg.deploymentId AND dreg.rn = 1
GROUP BY dreg.regionName
ORDER BY totalRevenue DESC;
 
 
-- ============================================================
-- QUERY 7: Resource utilization rate by data center
-- ============================================================
-- WHY THIS IS USEFUL: If a data center has 20 resources but only
-- 5 are being used, that is wasted capacity. If all 20 are in use,
-- the team might need to add more before new clients are turned
-- away. This query calculates what fraction of each data center's
-- resources are currently allocated to active deployments.
-- ============================================================

SELECT
    dc.name AS dataCenter,
    dc.city,
    az.zoneName,
    reg.regionName,
    COUNT(DISTINCT r.resourceId) AS totalResources,
    COUNT(DISTINCT CASE
        WHEN dr.deallocatedAt IS NULL AND dr.deploymentId IS NOT NULL
        THEN r.resourceId
    END) AS resourcesInUse,
    ROUND(
        COUNT(DISTINCT CASE
            WHEN dr.deallocatedAt IS NULL AND dr.deploymentId IS NOT NULL
            THEN r.resourceId
        END) * 100.0 / COUNT(DISTINCT r.resourceId),
        1
    ) AS utilizationPercent
FROM resource r
JOIN data_center dc ON r.datacenterId = dc.datacenterId
JOIN availability_zone az ON dc.zoneId = az.zoneId
JOIN region reg ON az.regionId = reg.regionId
LEFT JOIN deployment_resource dr ON r.resourceId = dr.resourceId
    AND dr.deallocatedAt IS NULL
GROUP BY dc.datacenterId, dc.name, dc.city, az.zoneName, reg.regionName
ORDER BY utilizationPercent DESC;


-- ============================================================
-- QUERY 8: Top 10 clients by total spend
-- ============================================================
-- WHY THIS IS USEFUL: Sales and account management teams need to
-- know who the biggest customers are. These clients deserve the
-- most attention and the best service. This also helps identify
-- whether revenue is concentrated in a few clients (risky) or
-- spread across many (healthy).
-- ============================================================

SELECT
    cl.clientId,
    cl.firstName || ' ' || cl.lastName AS clientName,
    COALESCE(o.orgName, 'Independent') AS organization,
    COUNT(DISTINCT d.deploymentId) AS deploymentCount,
    COUNT(c.chargeId) AS chargeCount,
    ROUND(SUM(c.amount), 2) AS totalSpend
FROM client cl
JOIN reservation res ON cl.clientId = res.clientId
JOIN deployment d ON res.reservationId = d.reservationId
JOIN charge c ON d.deploymentId = c.deploymentId
LEFT JOIN organization o ON cl.orgId = o.orgId
GROUP BY cl.clientId, clientName, organization
ORDER BY totalSpend DESC
LIMIT 10;


-- ============================================================
-- QUERY 9: Average deployment duration by resource type
-- ============================================================
-- WHY THIS IS USEFUL: Different workloads have different lifespans.
-- GPU deployments for ML training might run for weeks, while
-- compute instances for testing might last hours. Understanding
-- these patterns helps with capacity forecasting. If GPU
-- deployments average 60 days, the team knows those resources
-- will be locked up for a long time once reserved.
-- ============================================================

SELECT
    rt.typeName AS resourceType,
    rt.category,
    COUNT(DISTINCT d.deploymentId) AS deploymentCount,
    ROUND(AVG(
        julianday(COALESCE(d.stoppedAt, '2026-03-31')) - julianday(d.startedAt)
    ), 1) AS avgDurationDays,
    ROUND(MIN(
        julianday(COALESCE(d.stoppedAt, '2026-03-31')) - julianday(d.startedAt)
    ), 1) AS minDurationDays,
    ROUND(MAX(
        julianday(COALESCE(d.stoppedAt, '2026-03-31')) - julianday(d.startedAt)
    ), 1) AS maxDurationDays
FROM deployment d
JOIN deployment_resource dr ON d.deploymentId = dr.deploymentId
JOIN resource r ON dr.resourceId = r.resourceId
JOIN resource_type rt ON r.resourceTypeId = rt.resourceTypeId
GROUP BY rt.typeName, rt.category
ORDER BY avgDurationDays DESC;


-- ============================================================
-- QUERY 10: Monthly charge trend over time
-- ============================================================
-- WHY THIS IS USEFUL: Is CloudNine growing? This is the most
-- basic business health metric. If monthly revenue is going up,
-- the company is doing well. If it is flat or declining, something
-- needs to change. This query supports the Monthly Revenue line
-- chart on the web interface's Reports page.
-- ============================================================

SELECT
    strftime('%Y-%m', c.chargedAt) AS month,
    COUNT(c.chargeId) AS chargeCount,
    ROUND(SUM(c.amount), 2) AS totalRevenue,
    ROUND(SUM(CASE WHEN st.category = 'compute' THEN c.amount ELSE 0 END), 2) AS computeRevenue,
    ROUND(SUM(CASE WHEN st.category = 'storage' THEN c.amount ELSE 0 END), 2) AS storageRevenue,
    ROUND(SUM(CASE WHEN st.category = 'network' THEN c.amount ELSE 0 END), 2) AS networkRevenue,
    ROUND(SUM(CASE WHEN st.category = 'support' THEN c.amount ELSE 0 END), 2) AS supportRevenue
FROM charge c
JOIN service_type st ON c.serviceTypeId = st.serviceTypeId
WHERE c.isProvisional = 0
GROUP BY strftime('%Y-%m', c.chargedAt)
ORDER BY month;


-- ============================================================
-- QUERY 11: Adjustment credits vs. surcharges by month
-- ============================================================
-- WHY THIS IS USEFUL: If CloudNine is giving back more in credits
-- than it collects in surcharges, that signals reliability problems
-- (outages, failures). If surcharges outpace credits, clients are
-- demanding a lot of emergency and after-hours support. Either way,
-- this trend tells management where operational improvements are
-- needed. It also validates that the adjustment table captures
-- real financial impact, not just notes.
-- ============================================================

SELECT
    strftime('%Y-%m', a.createdAt) AS month,
    COUNT(CASE WHEN a.adjustmentType = 'credit' THEN 1 END) AS creditCount,
    ROUND(SUM(CASE WHEN a.adjustmentType = 'credit' THEN a.amount ELSE 0 END), 2) AS totalCredits,
    COUNT(CASE WHEN a.adjustmentType = 'surcharge' THEN 1 END) AS surchargeCount,
    ROUND(SUM(CASE WHEN a.adjustmentType = 'surcharge' THEN a.amount ELSE 0 END), 2) AS totalSurcharges,
    ROUND(SUM(a.amount), 2) AS netAdjustment
FROM adjustment a
GROUP BY strftime('%Y-%m', a.createdAt)
ORDER BY month;
