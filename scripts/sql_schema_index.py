#!/usr/bin/env python3
"""Extract a navigation index from SQL text without executing it.

Input and output are single JSON objects on stdin/stdout. SQLFluff supplies the
syntax tree; this module deliberately models only table declarations, columns,
primary keys, and foreign keys. It is not a database or a SQL validator.
"""

from __future__ import annotations

import bisect
import json
import logging
import os
import sys
from typing import Any


def empty_index(dialect: str | None = None) -> dict[str, Any]:
    return {
        "version": 1,
        "dialect": dialect,
        "partial": False,
        "issues": [],
        "tables": [],
        "foreign_keys": [],
        "occurrences": [],
    }


def ascii_lower(value: str) -> str:
    # PostgreSQL UTF-8 identifiers and SQLite identifier comparisons fold ASCII
    # letters. Python casefold() would also merge distinct non-ASCII names.
    return value.translate(
        str.maketrans("ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz")
    )


class Indexer:
    def __init__(self, source: str, dialect: str) -> None:
        self.source = source
        self.dialect = dialect
        self.result = empty_index(dialect)
        self.line_starts = [0] + [
            i + 1 for i, char in enumerate(source) if char == "\n"
        ]
        self.tables: list[dict[str, Any]] = []
        self.foreign_keys: list[dict[str, Any]] = []
        self.local_references: list[tuple[dict[str, Any], Any, str]] = []
        self.next_id = 0

    def uid(self, kind: str) -> str:
        self.next_id += 1
        return f"{kind}:{self.next_id}"

    def point(self, offset: int) -> tuple[int, int]:
        offset = max(0, min(offset, len(self.source)))
        row = bisect.bisect_right(self.line_starts, offset) - 1
        return row + 1, len(self.source[self.line_starts[row] : offset].encode("utf-8"))

    def location(self, segment: Any) -> dict[str, int]:
        marker = segment.pos_marker
        start, end = marker.source_slice.start, marker.source_slice.stop
        lnum, col = self.point(start)
        end_lnum, end_col = self.point(end)
        return {"lnum": lnum, "col": col, "end_lnum": end_lnum, "end_col": end_col}

    def issue(self, message: str, segment: Any = None, *, partial: bool = True) -> None:
        issue: dict[str, Any] = {"message": message}
        if segment is not None and segment.pos_marker:
            issue["location"] = self.location(segment)
        self.result["issues"].append(issue)
        self.result["partial"] = self.result["partial"] or partial

    def occurrence(
        self, segment: Any, targets: list[str], kind: str, reason: str | None = None
    ) -> None:
        item: dict[str, Any] = {
            "location": self.location(segment),
            "targets": targets,
            "kind": kind,
        }
        if reason:
            item["reason"] = reason
        self.result["occurrences"].append(item)

    def identifier(self, segment: Any) -> tuple[str, str]:
        display = segment.raw
        value = display
        quoted = len(value) >= 2 and value[0] in ('"', "`", "[", "'")
        if quoted:
            closer = "]" if value[0] == "[" else value[0]
            value = value[1:-1].replace(closer * 2, closer)
        if self.dialect == "sqlite" or not quoted:
            value = ascii_lower(value)
        return display, value

    @staticmethod
    def identifiers(segment: Any) -> list[Any]:
        return [
            child
            for child in segment.segments
            if child.is_type("naked_identifier", "quoted_identifier", "quoted_literal")
        ]

    def parts(self, reference: Any) -> tuple[list[str], tuple[str, ...]]:
        identifiers = self.identifiers(reference)
        if reference.is_type("naked_identifier", "quoted_identifier", "quoted_literal"):
            identifiers = [reference]
        names = [self.identifier(child) for child in identifiers]
        return [name[0] for name in names], tuple(name[1] for name in names)

    @staticmethod
    def keywords(segment: Any) -> list[str]:
        return [
            child.raw.upper() for child in segment.segments if child.is_type("keyword")
        ]

    def table_candidates(self, key: tuple[str, ...]) -> list[dict[str, Any]]:
        if len(key) > 1:
            return [table for table in self.tables if table["_key"] == key]
        return [
            table
            for table in self.tables
            if table["_key"] and table["_key"][-1:] == key
        ]

    @staticmethod
    def column_candidates(table: dict[str, Any], key: str) -> list[dict[str, Any]]:
        return [column for column in table["columns"] if column["_key"] == key]

    def column_reference(self, table: dict[str, Any], segment: Any) -> None:
        names, keys = self.parts(segment)
        if keys:
            self.local_references.append((table, segment, keys[-1]))

    def primary_key(self, table: dict[str, Any], references: list[Any]) -> None:
        names: list[str] = []
        keys: list[str] = []
        for reference in references:
            display, canonical = self.parts(reference)
            if canonical:
                names.append(display[-1])
                keys.append(canonical[-1])
                self.column_reference(table, reference)
        if table["primary_key"] and keys != table["_primary_key_keys"]:
            self.issue(
                f"Multiple primary-key declarations for {table['qualified_name']}",
                references[0],
            )
        table["primary_key"] = names
        table["_primary_key_keys"] = keys

    def foreign_key(
        self, table: dict[str, Any], constraint: Any, source_references: list[Any]
    ) -> None:
        target = constraint.get_child("table_reference")
        if target is None:
            self.issue("Foreign-key target could not be extracted", constraint)
            return
        target_names, target_key = self.parts(target)
        if not target_key:
            self.issue("Foreign-key target identifier could not be extracted", target)
            return
        after_target = False
        target_references: list[Any] = []
        for child in constraint.segments:
            if child is target:
                after_target = True
            elif after_target and child.is_type("bracketed"):
                target_references = list(child.get_children("column_reference"))
                break
        sources = [self.parts(reference) for reference in source_references]
        targets = [self.parts(reference) for reference in target_references]
        for reference in source_references:
            self.column_reference(table, reference)
        self.foreign_keys.append(
            {
                "id": self.uid("fk"),
                "source_table_id": table["id"],
                "source_columns": [parts[0][-1] for parts in sources if parts[1]],
                "target_name": ".".join(target_names),
                "target_columns": [parts[0][-1] for parts in targets if parts[1]],
                "target_table_ids": [],
                "target_column_ids": [],
                "location": self.location(target),
                "status": "unresolved",
                "_source_table": table,
                "_source_keys": [parts[1][-1] for parts in sources if parts[1]],
                "_target_key": target_key,
                "_target_keys": [parts[1][-1] for parts in targets if parts[1]],
                "_target_segment": target,
                "_target_references": target_references,
            }
        )

    def column(
        self, table: dict[str, Any], definition: Any, *, reference: Any = None
    ) -> None:
        identifier = reference or next(iter(self.identifiers(definition)), None)
        if identifier is None:
            self.issue("Column identifier could not be extracted", definition)
            return
        # ALTER ADD COLUMN uses a column_reference rather than an identifier.
        if identifier.is_type("column_reference"):
            identifiers = self.identifiers(identifier)
            identifier = identifiers[-1] if identifiers else None
        if identifier is None:
            self.issue("Column identifier could not be extracted", definition)
            return
        name, key = self.identifier(identifier)
        data_type = definition.get_child("data_type")
        column = {
            "id": self.uid("column"),
            "name": name,
            "data_type": data_type.raw if data_type else "",
            "location": self.location(identifier),
            "_key": key,
        }
        if self.column_candidates(table, key):
            self.issue(
                f"Duplicate column {name} on {table['qualified_name']}", identifier
            )
        table["columns"].append(column)
        self.occurrence(identifier, [column["id"]], "column")
        for constraint in definition.get_children("column_constraint_segment"):
            keywords = self.keywords(constraint)
            if "PRIMARY" in keywords and "KEY" in keywords:
                if table["primary_key"] and table["_primary_key_keys"] != [key]:
                    self.issue(
                        f"Multiple primary-key declarations for {table['qualified_name']}",
                        constraint,
                    )
                table["primary_key"] = [name]
                table["_primary_key_keys"] = [key]
            if "REFERENCES" in keywords:
                # An inline FK's source is the column declaration itself.
                self.foreign_key(table, constraint, [identifier])

    def constraint(self, table: dict[str, Any], constraint: Any) -> None:
        keywords = self.keywords(constraint)
        first_bracket = constraint.get_child("bracketed")
        references = (
            list(first_bracket.get_children("column_reference"))
            if first_bracket
            else []
        )
        if "PRIMARY" in keywords and "KEY" in keywords:
            self.primary_key(table, references)
        if "FOREIGN" in keywords and "REFERENCES" in keywords:
            self.foreign_key(table, constraint, references)

    def create_table(self, statement: Any) -> None:
        reference = statement.get_child("table_reference")
        if reference is None:
            self.issue("Table identifier could not be extracted", statement)
            return
        names, key = self.parts(reference)
        if not key:
            self.issue("Table identifier could not be extracted", reference)
            return
        table = {
            "id": self.uid("table"),
            "name": names[-1],
            "qualified_name": ".".join(names),
            "location": self.location(reference),
            "range": self.location(statement),
            "columns": [],
            "primary_key": [],
            "_key": key,
            "_primary_key_keys": [],
        }
        if any(existing["_key"] == key for existing in self.tables):
            self.issue(
                f"Duplicate table declaration {table['qualified_name']}", reference
            )
        self.tables.append(table)
        self.occurrence(reference, [table["id"]], "table")
        bracket = statement.get_child("bracketed")
        if bracket is None:
            self.issue(
                "CREATE TABLE without explicit columns is not indexed completely",
                statement,
            )
            return
        for definition in bracket.get_children("column_definition"):
            self.column(table, definition)
        for constraint in bracket.get_children("table_constraint"):
            self.constraint(table, constraint)
        if not table["columns"]:
            self.issue("No explicit column definitions found for this table", statement)
        if "INHERITS" in self.keywords(statement) or any(
            child.is_type("keyword") and child.raw.upper() == "LIKE"
            for child in bracket.segments
        ):
            self.issue("Inherited/LIKE columns are not expanded", statement)

    def alter_table(self, statement: Any) -> None:
        reference = statement.get_child("table_reference")
        if reference is None:
            self.issue("ALTER TABLE target could not be extracted", statement)
            return
        names, key = self.parts(reference)
        candidates = self.table_candidates(key)
        self.occurrence(reference, [table["id"] for table in candidates], "table")
        if len(candidates) != 1:
            self.issue(
                f"ALTER TABLE target {'.'.join(names)} is missing or ambiguous at this statement",
                reference,
            )
            return
        table = candidates[0]
        actions = statement.get_children("alter_table_action_segment") or [statement]
        for action in actions:
            keywords = self.keywords(action)
            if "ADD" in keywords:
                constraint = action.get_child("table_constraint")
                definition = action.get_child("column_definition")
                reference = action.get_child("column_reference")
                if constraint is not None:
                    self.constraint(table, constraint)
                elif definition is not None:
                    self.column(table, definition)
                elif (
                    reference is not None and action.get_child("data_type") is not None
                ):
                    self.column(table, action, reference=reference)
                else:
                    self.issue("This ALTER TABLE ADD form is not indexed", action)
            elif any(
                word in keywords
                for word in ("RENAME", "DROP", "TYPE", "INHERIT", "ATTACH", "DETACH")
            ):
                self.issue(
                    "This schema-changing ALTER TABLE form is not applied to the index",
                    action,
                )
            elif "OWNER" not in keywords and "VALIDATE" not in keywords:
                # Even metadata forms can evolve between SQLFluff dialects.
                # Be explicit when a statement's effect has not been modeled.
                self.issue("This ALTER TABLE form is not applied to the index", action)

    def resolve(self) -> None:
        for table, reference, key in self.local_references:
            candidates = self.column_candidates(table, key)
            self.occurrence(
                reference,
                [column["id"] for column in candidates],
                "column",
                None
                if len(candidates) == 1
                else "Source column is missing or ambiguous",
            )
        for foreign_key in self.foreign_keys:
            candidates = self.table_candidates(foreign_key["_target_key"])
            foreign_key["target_table_ids"] = [table["id"] for table in candidates]
            self.occurrence(
                foreign_key["_target_segment"],
                foreign_key["target_table_ids"],
                "table",
                None
                if len(candidates) == 1
                else "Referenced table is missing or ambiguous in this file",
            )
            if len(candidates) > 1:
                foreign_key["status"] = "ambiguous"
            if len(candidates) != 1:
                all_column_ids: list[str] = []
                for reference, key in zip(
                    foreign_key["_target_references"], foreign_key["_target_keys"]
                ):
                    columns = [
                        column
                        for candidate in candidates
                        for column in self.column_candidates(candidate, key)
                    ]
                    targets = [column["id"] for column in columns]
                    all_column_ids.extend(targets)
                    self.occurrence(
                        reference,
                        targets,
                        "column",
                        "Referenced table is missing or ambiguous in this file",
                    )
                foreign_key["target_column_ids"] = all_column_ids
                continue
            target = candidates[0]
            target_keys = foreign_key["_target_keys"]
            if not target_keys:
                target_keys = target["_primary_key_keys"]
                foreign_key["target_columns"] = list(target["primary_key"])
            matches = [self.column_candidates(target, key) for key in target_keys]
            foreign_key["target_column_ids"] = [
                column["id"] for group in matches for column in group
            ]
            for reference, group in zip(foreign_key["_target_references"], matches):
                self.occurrence(
                    reference,
                    [column["id"] for column in group],
                    "column",
                    None
                    if len(group) == 1
                    else "Referenced column is missing or ambiguous",
                )
            source_matches = [
                self.column_candidates(foreign_key["_source_table"], key)
                for key in foreign_key["_source_keys"]
            ]
            if any(len(group) > 1 for group in matches + source_matches):
                foreign_key["status"] = "ambiguous"
            elif (
                target_keys
                and len(target_keys) == len(foreign_key["_source_keys"])
                and all(len(group) == 1 for group in matches + source_matches)
            ):
                foreign_key["status"] = "resolved"

        covered_columns: set[tuple[str, str]] = set()
        for foreign_key in self.foreign_keys:
            if foreign_key["status"] == "resolved":
                continue
            qualifier = " unambiguously" if foreign_key["status"] == "ambiguous" else ""
            self.issue(
                f"Cannot resolve foreign key to {foreign_key['target_name']}"
                f"{qualifier} within this file",
                foreign_key["_target_segment"],
            )
            covered_columns.update(
                (foreign_key["source_table_id"], key)
                for key in foreign_key["_source_keys"]
            )
            for table in self.tables:
                if table["id"] in foreign_key["target_table_ids"]:
                    covered_columns.update(
                        (table["id"], key)
                        for key in (
                            foreign_key["_target_keys"] or table["_primary_key_keys"]
                        )
                    )
        for table, reference, key in self.local_references:
            if (
                len(self.column_candidates(table, key)) != 1
                and (table["id"], key) not in covered_columns
            ):
                self.issue(
                    f"Cannot resolve source column {reference.raw} on "
                    f"{table['qualified_name']} within this file",
                    reference,
                )
                covered_columns.add((table["id"], key))

    def run(self, tree: Any) -> dict[str, Any]:
        for wrapper in tree.get_children("statement"):
            statement = next(
                (segment for segment in wrapper.segments if segment.is_code), None
            )
            if statement is None:
                continue
            if statement.is_type("create_table_statement", "create_table_as_statement"):
                self.create_table(statement)
            elif statement.is_type("alter_table_statement"):
                self.alter_table(statement)
            elif statement.is_type("drop_table_statement"):
                self.issue(
                    "DROP TABLE is not applied; the index shows declarations rather than final database state",
                    statement,
                )
            elif statement.is_type(
                "do_statement",
                "execute_statement",
                "call_statement",
                "create_function_statement",
            ):
                self.issue(
                    "Procedural/dynamic SQL is not evaluated by the offline index",
                    statement,
                )
        self.resolve()
        for table in self.tables:
            for column in table["columns"]:
                column.pop("_key")
            table.pop("_key")
            table.pop("_primary_key_keys")
        for foreign_key in self.foreign_keys:
            for key in list(foreign_key):
                if key.startswith("_"):
                    del foreign_key[key]
        self.result["tables"] = self.tables
        self.result["foreign_keys"] = self.foreign_keys
        return self.result


def build_index(
    source: str, dialect: str | None = None, filename: str | None = None
) -> dict[str, Any]:
    """Parse the supplied text, using a file path only to discover configuration."""
    logging.disable(logging.CRITICAL)
    result = empty_index(dialect)
    try:
        from sqlfluff.core import FluffConfig, Linter

        overrides: dict[str, Any] = {
            "templater": "raw",
            "large_file_skip_byte_limit": 0,
        }
        if dialect:
            overrides["dialect"] = dialect
        config = FluffConfig.from_path(filename or os.getcwd(), overrides=overrides)
        dialect = config.get("dialect")
        result["dialect"] = dialect
        if dialect not in ("postgres", "sqlite"):
            raise ValueError(
                "Offline schema indexing supports the postgres and sqlite dialects"
            )
        indexer = Indexer(source, dialect)
        parsed = Linter(config=config).parse_string(
            source, fname=filename or "untitled.sql"
        )
        for violation in parsed.violations:
            issue: dict[str, Any] = {"message": violation.desc()}
            line = max(1, getattr(violation, "line_no", 1))
            column = max(1, getattr(violation, "line_pos", 1))
            if line <= len(indexer.line_starts):
                offset = indexer.line_starts[line - 1] + column - 1
                row, byte_col = indexer.point(offset)
                issue["location"] = {
                    "lnum": row,
                    "col": byte_col,
                    "end_lnum": row,
                    "end_col": byte_col,
                }
            indexer.result["issues"].append(issue)
            indexer.result["partial"] = True
        if parsed.tree is None:
            indexer.issue("SQLFluff did not produce a syntax tree")
            return indexer.result
        return indexer.run(parsed.tree)
    except (
        Exception
    ) as error:  # Configuration/parser errors must remain machine-readable.
        result["partial"] = True
        result["issues"].append(
            {"message": f"Unable to index schema: {str(error)[:2000]}"}
        )
        return result


def main() -> int:
    try:
        request = json.load(sys.stdin)
        if not isinstance(request, dict) or not isinstance(request.get("source"), str):
            raise ValueError("Expected a JSON object containing a source string")
        if request.get("dialect") is not None and not isinstance(
            request["dialect"], str
        ):
            raise ValueError("dialect must be a string")
        if request.get("filename") is not None and not isinstance(
            request["filename"], str
        ):
            raise ValueError("filename must be a string")
        result = build_index(
            request["source"], request.get("dialect"), request.get("filename")
        )
    except Exception as error:
        result = empty_index()
        result["partial"] = True
        result["issues"].append(
            {"message": f"Unable to read schema request: {str(error)[:2000]}"}
        )
    print(json.dumps(result, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
