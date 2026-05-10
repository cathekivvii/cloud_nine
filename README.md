# CloudNine App

CloudNine is a Flask and SQLite web app for managing cloud infrastructure operations, including resources, reservations, deployments, billing, maintenance, and reporting.

## Project Structure

- `app.py` - Flask application, routes, helper functions, and SQLite access.
- `schema.sql` - database schema and seed data.
- `cloudnine.db` - local SQLite database used by the app.
- `templates/` - HTML templates rendered by Flask.
- `static/css/style.css` - app styling.

## Run Locally

Install Flask in your Python environment:

```bash
python3 -m pip install flask
```

Start the development server:

```bash
python3 app.py
```

The app runs at:

```text
http://127.0.0.1:5000
```

## Reset the Database

To rebuild `cloudnine.db` from `schema.sql`:

```bash
python3 -c "from app import init_db; init_db()"
```

This deletes and recreates the local database.

## Quick Check

Run a syntax check before submitting changes:

```bash
python3 -m py_compile app.py
```
