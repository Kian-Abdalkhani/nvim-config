"""Behavior checks for the offline index; run with SQLFluff's Python runtime."""

import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


BACKEND = Path(__file__).resolve().parents[2] / "scripts" / "sql_schema_index.py"
SPEC = importlib.util.spec_from_file_location("sql_schema_index", BACKEND)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


def index(source, dialect="postgres", filename=None):
    return MODULE.build_index(source, dialect, filename)


def source_text(source, location):
    lines = source.splitlines(keepends=True)
    if location["lnum"] != location["end_lnum"]:
        raise AssertionError("Expected a one-line identifier")
    return (
        lines[location["lnum"] - 1]
        .encode()[location["col"] : location["end_col"]]
        .decode()
    )


class SchemaIndexTests(unittest.TestCase):
    def test_postgres_inline_fk_forward_reference(self):
        result = index(
            "CREATE TABLE orders (owner integer REFERENCES users(id)); CREATE TABLE users(id integer PRIMARY KEY);"
        )
        self.assertFalse(result["partial"], result["issues"])
        self.assertEqual(result["foreign_keys"][0]["source_columns"], ["owner"])
        self.assertEqual(result["foreign_keys"][0]["status"], "resolved")
        self.assertEqual(
            result["foreign_keys"][0]["target_column_ids"],
            [result["tables"][1]["columns"][0]["id"]],
        )

    def test_named_composite_fk_and_pk(self):
        result = index("""CREATE TABLE public.parent(a integer, b integer, PRIMARY KEY(a,b));
CREATE TABLE public.child(x integer, y integer,
CONSTRAINT fk_pair FOREIGN KEY(x,y) REFERENCES public.parent(a,b));""")
        self.assertFalse(result["partial"], result["issues"])
        relation = result["foreign_keys"][0]
        self.assertEqual(relation["source_columns"], ["x", "y"])
        self.assertEqual(relation["target_columns"], ["a", "b"])
        self.assertEqual(relation["status"], "resolved")
        self.assertEqual(result["tables"][0]["primary_key"], ["a", "b"])
        self.assertEqual(len(relation["target_column_ids"]), 2)

    def test_sqlite_implicit_composite_target_pk(self):
        result = index(
            """CREATE TABLE parent(a integer, b integer, PRIMARY KEY(a,b));
CREATE TABLE child(x integer, y integer, FOREIGN KEY(x,y) REFERENCES parent);""",
            "sqlite",
        )
        relation = result["foreign_keys"][0]
        self.assertFalse(result["partial"], result["issues"])
        self.assertEqual(relation["target_columns"], ["a", "b"])
        self.assertEqual(relation["status"], "resolved")

    def test_quoted_postgres_identifiers_and_case(self):
        result = index("""CREATE TABLE "Users"("Id" integer PRIMARY KEY);
CREATE TABLE USERS(id integer PRIMARY KEY);
CREATE TABLE c(a integer REFERENCES "Users"("Id"), b integer REFERENCES users(ID));""")
        self.assertFalse(result["partial"], result["issues"])
        relations = result["foreign_keys"]
        self.assertTrue(all(relation["status"] == "resolved" for relation in relations))
        self.assertNotEqual(
            relations[0]["target_table_ids"], relations[1]["target_table_ids"]
        )
        self.assertEqual(result["tables"][0]["name"], '"Users"')

    def test_sqlite_identifiers_are_ascii_case_insensitive(self):
        result = index(
            'CREATE TABLE "PARENT"("Id" integer PRIMARY KEY); CREATE TABLE c(x integer REFERENCES parent(id));',
            "sqlite",
        )
        self.assertEqual(result["foreign_keys"][0]["status"], "resolved", result)

    def test_unicode_locations_use_utf8_bytes(self):
        source = 'CREATE TABLE "顾客" ("编号" INTEGER PRIMARY KEY);\nCREATE TABLE "子" ("关联" integer REFERENCES "顾客"("编号"));'
        result = index(source, "sqlite")
        self.assertFalse(result["partial"], result["issues"])
        for table in result["tables"]:
            self.assertEqual(
                source_text(source, table["location"]), table["qualified_name"]
            )
            for column in table["columns"]:
                self.assertEqual(
                    source_text(source, column["location"]), column["name"]
                )
        relation = result["foreign_keys"][0]
        self.assertEqual(source_text(source, relation["location"]), '"顾客"')
        self.assertEqual(relation["status"], "resolved")

    def test_schema_qualified_targets_and_ambiguous_unqualified_targets(self):
        result = index("""CREATE TABLE a.parent(id integer PRIMARY KEY);
CREATE TABLE b.parent(id integer PRIMARY KEY);
CREATE TABLE child(x integer REFERENCES parent(id), y integer REFERENCES a.parent(id));""")
        self.assertEqual(result["foreign_keys"][0]["status"], "ambiguous")
        self.assertEqual(len(result["foreign_keys"][0]["target_table_ids"]), 2)
        self.assertEqual(len(result["foreign_keys"][0]["target_column_ids"]), 2)
        self.assertEqual(result["foreign_keys"][1]["status"], "resolved")
        self.assertTrue(result["partial"])
        self.assertEqual(len(result["issues"]), 1)
        self.assertIn("unambiguously within this file", result["issues"][0]["message"])
        self.assertEqual(
            result["issues"][0]["location"], result["foreign_keys"][0]["location"]
        )

    def test_missing_table_and_column_are_unresolved(self):
        result = index(
            "CREATE TABLE p(id integer PRIMARY KEY); CREATE TABLE c(a integer REFERENCES absent(id), b integer REFERENCES p(nope));"
        )
        self.assertEqual(
            [relation["status"] for relation in result["foreign_keys"]],
            ["unresolved", "unresolved"],
        )
        self.assertEqual(result["foreign_keys"][0]["target_table_ids"], [])
        self.assertEqual(result["foreign_keys"][1]["target_column_ids"], [])
        self.assertTrue(
            any(occurrence.get("reason") for occurrence in result["occurrences"])
        )
        self.assertTrue(result["partial"])
        self.assertEqual(len(result["issues"]), 2)
        self.assertTrue(
            all("within this file" in issue["message"] for issue in result["issues"])
        )

    def test_missing_source_fk_column_has_one_relation_issue(self):
        result = index(
            "CREATE TABLE p(id integer PRIMARY KEY); "
            "CREATE TABLE c(id integer, FOREIGN KEY(missing) REFERENCES p(id));"
        )
        self.assertTrue(result["partial"])
        self.assertEqual(result["foreign_keys"][0]["status"], "unresolved")
        self.assertEqual(len(result["issues"]), 1)
        self.assertIn("Cannot resolve foreign key", result["issues"][0]["message"])

    def test_missing_source_primary_key_column_has_issue(self):
        result = index("CREATE TABLE p(id integer, PRIMARY KEY(missing));")
        self.assertTrue(result["partial"])
        self.assertEqual(len(result["issues"]), 1)
        self.assertIn(
            "Cannot resolve source column missing", result["issues"][0]["message"]
        )

    def test_ambiguous_source_key_column_has_issue(self):
        result = index("CREATE TABLE p(id integer, ID integer, PRIMARY KEY(id));")
        self.assertTrue(result["partial"])
        self.assertTrue(
            any(
                "Cannot resolve source column" in issue["message"]
                for issue in result["issues"]
            )
        )

    def test_postgres_alter_add_column_and_dump_style_constraints(self):
        result = index("""CREATE TABLE p(id integer);
CREATE TABLE c(id integer);
ALTER TABLE ONLY p ADD CONSTRAINT p_pkey PRIMARY KEY(id);
ALTER TABLE c ADD COLUMN p_id integer;
ALTER TABLE ONLY c ADD CONSTRAINT c_pkey PRIMARY KEY(id);
ALTER TABLE ONLY c ADD CONSTRAINT c_fk FOREIGN KEY(p_id) REFERENCES p(id);""")
        self.assertFalse(result["partial"], result["issues"])
        self.assertEqual(
            [column["name"] for column in result["tables"][1]["columns"]],
            ["id", "p_id"],
        )
        self.assertEqual(result["tables"][0]["primary_key"], ["id"])
        self.assertEqual(result["foreign_keys"][0]["status"], "resolved")

    def test_sqlite_alter_add_column_with_inline_reference(self):
        result = index(
            "CREATE TABLE p(id integer PRIMARY KEY); CREATE TABLE c(id integer); ALTER TABLE c ADD COLUMN p_id integer REFERENCES p(id);",
            "sqlite",
        )
        self.assertFalse(result["partial"], result["issues"])
        self.assertEqual(result["foreign_keys"][0]["status"], "resolved")

    def test_unsupported_alter_reports_partial(self):
        result = index(
            "CREATE TABLE t(id integer); ALTER TABLE t RENAME COLUMN id TO renamed;"
        )
        self.assertTrue(result["partial"])
        self.assertTrue(
            any("not applied" in issue["message"] for issue in result["issues"])
        )

    def test_alter_before_create_is_not_silently_reordered(self):
        result = index(
            "ALTER TABLE t ADD COLUMN x integer; CREATE TABLE t(id integer);"
        )
        self.assertTrue(result["partial"])
        self.assertEqual(
            [column["name"] for column in result["tables"][0]["columns"]], ["id"]
        )

    def test_drop_and_dynamic_sql_are_partial(self):
        result = index(
            "CREATE TABLE t(id integer); DROP TABLE t; DO $$ BEGIN EXECUTE 'CREATE TABLE hidden(id integer)'; END $$;"
        )
        self.assertTrue(result["partial"])
        self.assertEqual(len(result["tables"]), 1)
        self.assertTrue(
            any("dynamic" in issue["message"] for issue in result["issues"])
        )

    def test_ctas_is_explicitly_partial(self):
        result = index("CREATE TABLE t AS SELECT 1 AS id;")
        self.assertTrue(result["partial"])
        self.assertEqual(result["tables"][0]["columns"], [])

    def test_parse_errors_keep_usable_declarations_and_report_partial(self):
        result = index("CREATE TABLE valid(id integer); CREATE TABLE broken (;")
        self.assertTrue(result["partial"])
        self.assertTrue(result["issues"])
        self.assertEqual(result["tables"][0]["name"], "valid")

    def test_project_dialect_and_raw_templater(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / ".sqlfluff").write_text(
                "[sqlfluff]\ndialect=sqlite\ntemplater=jinja\n"
            )
            result = index(
                "CREATE TABLE p(id integer PRIMARY KEY AUTOINCREMENT);",
                None,
                str(root / "schema.sql"),
            )
            self.assertEqual(result["dialect"], "sqlite")
            self.assertFalse(result["partial"], result["issues"])

    def test_project_jinja_library_is_not_executed(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            library = root / "template_library"
            library.mkdir()
            marker = root / "executed"
            (library / "__init__.py").write_text(
                f"from pathlib import Path\nPath({str(marker)!r}).write_text('executed')\n"
            )
            (root / ".sqlfluff").write_text(
                "[sqlfluff]\ndialect=postgres\ntemplater=jinja\n"
                f"[sqlfluff:templater:jinja]\nlibrary_path={library}\n"
            )
            result = index(
                "CREATE TABLE p(id integer);", None, str(root / "schema.sql")
            )
            self.assertFalse(result["partial"], result["issues"])
            self.assertFalse(marker.exists())

    def test_templated_sql_is_reported_as_partial_raw_sql(self):
        result = index("CREATE TABLE {{ table_name }} (id integer);")
        self.assertTrue(result["partial"])
        self.assertTrue(result["issues"])

    def test_input_buffer_is_used_instead_of_filename_contents(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "schema.sql"
            path.write_text("CREATE TABLE stale(id integer);")
            result = index("CREATE TABLE unsaved(id integer);", "postgres", str(path))
            self.assertEqual(result["tables"][0]["name"], "unsaved")
            self.assertIn("stale", path.read_text())

    def test_large_schema_is_not_silently_skipped(self):
        source = "-- " + "large file " * 2200 + "\nCREATE TABLE present(id integer);"
        result = index(source)
        self.assertFalse(result["partial"], result["issues"])
        self.assertEqual(result["tables"][0]["name"], "present")

    def test_invalid_dialect_and_config_return_json_issues(self):
        result = index("CREATE TABLE t(id integer);", "mysql")
        self.assertTrue(result["partial"])
        self.assertIn("postgres and sqlite", result["issues"][0]["message"])
        with tempfile.TemporaryDirectory() as directory:
            (Path(directory) / ".sqlfluff").write_text("not an ini file")
            result = index(
                "CREATE TABLE t(id integer);", None, str(Path(directory) / "schema.sql")
            )
            self.assertTrue(result["partial"])
            self.assertTrue(result["issues"])

    def test_cli_is_json_only_and_never_reads_sql_from_disk(self):
        request = {
            "source": "CREATE TABLE stdin_only(id integer);",
            "dialect": "postgres",
            "filename": "/nonexistent/schema.sql",
        }
        completed = subprocess.run(
            [sys.executable, str(BACKEND)],
            input=json.dumps(request),
            text=True,
            capture_output=True,
            check=True,
        )
        result = json.loads(completed.stdout)
        self.assertEqual(result["tables"][0]["name"], "stdin_only")
        self.assertEqual(completed.stderr, "")


if __name__ == "__main__":
    unittest.main()
