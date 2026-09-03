"""Shared Azure SQL Database connection helper.

Connects to the logical server at <server>.database.windows.net over ODBC
Driver 18, which defaults to Encrypt=yes -- Azure SQL refuses unencrypted
connections, so that default is left alone rather than turned off.

Credentials come from .env (never committed). Keys: AZURE_SQL_SERVER,
AZURE_SQL_DATABASE, AZURE_SQL_USER, AZURE_SQL_PASSWORD.
"""
import os

import pyodbc
from dotenv import load_dotenv

load_dotenv(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".env"))

DRIVER = "ODBC Driver 18 for SQL Server"


def _require(name):
    value = os.environ.get(name, "").strip()
    if not value:
        raise SystemExit(
            f"{name} is empty in .env.\n"
            "Fill in the values from the Azure portal -> your SQL database -> "
            "Overview (server name) and the login you created with the server."
        )
    return value


def connection_string(database=None):
    """Build an ODBC string. Pass database="master" to reach the server
    itself -- useful when the database name in .env is wrong and you need to
    ask the server what databases actually exist."""
    server = _require("AZURE_SQL_SERVER")
    # Accept either the bare name or the full FQDN in .env.
    if "." not in server:
        server = f"{server}.database.windows.net"
    return (
        f"DRIVER={{{DRIVER}}};"
        f"SERVER=tcp:{server},1433;"
        f"DATABASE={database or _require('AZURE_SQL_DATABASE')};"
        f"UID={_require('AZURE_SQL_USER')};"
        f"PWD={_require('AZURE_SQL_PASSWORD')};"
        "Encrypt=yes;TrustServerCertificate=no;Connection Timeout=30;"
    )


def get_connection(database=None):
    return pyodbc.connect(connection_string(database))


DATABASE = os.environ.get("AZURE_SQL_DATABASE", "")
