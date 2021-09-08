module DataSources.SqlParser.Parsers.CreateTable exposing (ParsedCheck, ParsedColumn, ParsedIndex, ParsedPrimaryKey, ParsedTable, ParsedUnique, parseCreateTable, parseCreateTableColumn)

import DataSources.SqlParser.Parsers.AlterTable as AlterTable exposing (TableConstraint(..), parseAlterTableAddConstraint)
import DataSources.SqlParser.Utils.Helpers exposing (buildColumnName, buildConstraintName, buildRawSql, buildSchemaName, buildSqlLine, buildTableName, commaSplit)
import DataSources.SqlParser.Utils.Types exposing (ParseError, RawSql, SqlColumnName, SqlColumnType, SqlColumnValue, SqlConstraintName, SqlForeignKeyRef, SqlPredicate, SqlSchemaName, SqlStatement, SqlTableName)
import Libs.List as L
import Libs.Maybe as M
import Libs.Nel as Nel exposing (Nel)
import Libs.Regex as R


type alias ParsedTable =
    { schema : Maybe SqlSchemaName
    , table : SqlTableName
    , columns : Nel ParsedColumn
    , primaryKey : Maybe ParsedPrimaryKey
    , uniques : List ParsedUnique
    , indexes : List ParsedIndex
    , checks : List ParsedCheck
    , source : SqlStatement
    }


type alias ParsedColumn =
    { name : SqlColumnName
    , kind : SqlColumnType
    , nullable : Bool
    , default : Maybe SqlColumnValue
    , primaryKey : Maybe SqlConstraintName
    , foreignKey : Maybe ( SqlConstraintName, SqlForeignKeyRef )
    }


type alias ParsedPrimaryKey =
    { name : Maybe SqlConstraintName, columns : Nel SqlColumnName }


type alias ParsedUnique =
    { name : SqlConstraintName, columns : Nel SqlColumnName, definition : String }


type alias ParsedIndex =
    { name : SqlConstraintName, columns : Nel SqlColumnName, definition : String }


type alias ParsedCheck =
    { name : SqlConstraintName, predicate : SqlPredicate }


parseCreateTable : SqlStatement -> Result (List ParseError) ParsedTable
parseCreateTable statement =
    case statement |> buildSqlLine |> R.matches "^CREATE TABLE\\s+(?:(?<schema>[^ .]+)\\.)?(?<table>[^ .]+)\\s*\\((?<body>[^;]+?)\\)(?:\\s+WITH\\s+\\((?<options>.*?)\\))?(?:[^)]*)?;$" of
        schema :: (Just table) :: (Just body) :: _ :: [] ->
            let
                ( constraints, columns ) =
                    commaSplit body
                        |> List.map String.trim
                        |> List.partition (\col -> col |> String.toUpper |> (\colUp -> [ "CONSTRAINT ", "PRIMARY KEY ", "UNIQUE KEY ", "KEY `" ] |> List.any (\cons -> colUp |> String.startsWith cons)))
            in
            Result.map5
                (\cols pk uniques indexes parsedConstraints ->
                    { schema = schema |> Maybe.map buildSchemaName
                    , table = table |> buildTableName
                    , columns = cols
                    , primaryKey = (pk ++ (parsedConstraints |> List.filterMap primaryKeyConstraints)) |> List.head
                    , uniques = uniques ++ (parsedConstraints |> List.filterMap uniqueKeyConstraints)
                    , indexes = indexes
                    , checks = parsedConstraints |> List.filterMap checkConstraints
                    , source = statement
                    }
                )
                (columns |> List.map parseCreateTableColumn |> L.resultSeq |> Result.andThen (\cols -> cols |> Nel.fromList |> Result.fromMaybe [ "Create table can't have empty columns" ]))
                (constraints |> List.filter (String.startsWith "PRIMARY KEY") |> List.map parseCreateTablePrimaryKey |> L.resultSeq)
                (constraints |> List.filter (String.startsWith "UNIQUE KEY") |> List.map parseCreateTableUniqueKey |> L.resultSeq)
                (constraints |> List.filter (String.startsWith "KEY") |> List.map parseCreateTableKey |> L.resultSeq)
                (constraints |> List.filter (String.startsWith "CONSTRAINT") |> List.map (\c -> ("ADD " ++ c) |> parseAlterTableAddConstraint) |> L.resultSeq |> Result.mapError (\errs -> errs |> List.concatMap identity))

        _ ->
            Err [ "Can't parse table: '" ++ buildRawSql statement ++ "'" ]


parseCreateTableColumn : RawSql -> Result ParseError ParsedColumn
parseCreateTableColumn sql =
    case sql |> R.matches "^(?<name>[^ ]+)\\s+(?<type>.*?)(?:\\s+DEFAULT\\s+(?<default1>.*?))?(?<nullable>\\s+NOT NULL)?(?:\\s+DEFAULT\\s+(?<default2>.*?))?(?:\\s+CONSTRAINT\\s+(?<constraint>.*))?(?: AUTO_INCREMENT)?$" of
        (Just name) :: (Just kind) :: default1 :: nullable :: default2 :: maybeConstraint :: [] ->
            maybeConstraint
                |> Maybe.map
                    (\constraint ->
                        if constraint |> String.toUpper |> String.contains "PRIMARY KEY" then
                            parseCreateTableColumnPrimaryKey constraint |> Result.map (\pk -> ( Just pk, Nothing ))

                        else if constraint |> String.toUpper |> String.contains "REFERENCES" then
                            parseCreateTableColumnForeignKey constraint |> Result.map (\fk -> ( Nothing, Just fk ))

                        else
                            Err ("Constraint not handled: '" ++ constraint ++ "' in create table")
                    )
                |> Maybe.withDefault (Ok ( Nothing, Nothing ))
                |> Result.map (\( pk, fk ) -> { name = name |> buildColumnName, kind = kind, nullable = nullable == Nothing, default = default1 |> M.orElse default2, primaryKey = pk, foreignKey = fk })

        _ ->
            Err ("Can't parse column: '" ++ sql ++ "'")


parseCreateTableColumnPrimaryKey : RawSql -> Result ParseError SqlConstraintName
parseCreateTableColumnPrimaryKey constraint =
    case constraint |> R.matches "^(?<constraint>[^ ]+)\\s+PRIMARY KEY$" of
        (Just constraintName) :: [] ->
            Ok constraintName

        _ ->
            Err ("Can't parse primary key: '" ++ constraint ++ "' in create table")


parseCreateTableColumnForeignKey : RawSql -> Result ParseError ( SqlConstraintName, SqlForeignKeyRef )
parseCreateTableColumnForeignKey constraint =
    case constraint |> R.matches "^(?<constraint>[^ ]+)\\s+REFERENCES\\s+(?:(?<schema>[^ .]+)\\.)?(?<table>[^ .]+)(?:\\.(?<column>[^ .]+))?$" of
        (Just constraintName) :: (Just table) :: (Just column) :: Nothing :: [] ->
            Ok ( constraintName, { schema = Nothing, table = table, column = Just column } )

        (Just constraintName) :: schema :: (Just table) :: column :: [] ->
            Ok ( constraintName, { schema = schema, table = table, column = column } )

        _ ->
            Err ("Can't parse foreign key: '" ++ constraint ++ "' in create table")


parseCreateTablePrimaryKey : RawSql -> Result ParseError ParsedPrimaryKey
parseCreateTablePrimaryKey sql =
    case sql |> R.matches "^PRIMARY KEY \\((?<columns>[^)]+)\\)$" of
        (Just columns) :: [] ->
            columns
                |> String.split ","
                |> List.map buildColumnName
                |> Nel.fromList
                |> Maybe.map (\cols -> { name = Nothing, columns = cols })
                |> Result.fromMaybe "Primary key can't have no column"

        _ ->
            Err ("Can't parse table primary key: '" ++ sql ++ "'")


parseCreateTableUniqueKey : RawSql -> Result ParseError ParsedUnique
parseCreateTableUniqueKey sql =
    case sql |> R.matches "^UNIQUE KEY (?<name>[^ ]+) \\((?<columns>[^)]+)\\)$" of
        (Just name) :: (Just columns) :: [] ->
            columns
                |> String.split ","
                |> List.map buildColumnName
                |> Nel.fromList
                |> Result.fromMaybe "Unique key can't have no column"
                |> Result.map (\cols -> { name = name |> buildConstraintName, columns = cols, definition = sql })

        _ ->
            Err ("Can't parse table unique key: '" ++ sql ++ "'")


parseCreateTableKey : RawSql -> Result ParseError ParsedIndex
parseCreateTableKey sql =
    case sql |> R.matches "^KEY (?<name>[^ ]+) \\((?<columns>[^)]+)\\)$" of
        (Just name) :: (Just columns) :: [] ->
            columns
                |> String.split ","
                |> List.map buildColumnName
                |> Nel.fromList
                |> Result.fromMaybe "Key can't have no column"
                |> Result.map (\cols -> { name = name |> buildConstraintName, columns = cols, definition = sql })

        _ ->
            Err ("Can't parse table key: '" ++ sql ++ "'")


primaryKeyConstraints : TableConstraint -> Maybe ParsedPrimaryKey
primaryKeyConstraints constraint =
    case constraint of
        AlterTable.ParsedPrimaryKey name columns ->
            Just { name = name, columns = columns }

        _ ->
            Nothing


uniqueKeyConstraints : TableConstraint -> Maybe ParsedUnique
uniqueKeyConstraints constraint =
    case constraint of
        AlterTable.ParsedUnique name { columns, definition } ->
            Just { name = name, columns = columns, definition = definition }

        _ ->
            Nothing


checkConstraints : TableConstraint -> Maybe ParsedCheck
checkConstraints constraint =
    case constraint of
        AlterTable.ParsedCheck name predicate ->
            Just { name = name, predicate = predicate }

        _ ->
            Nothing
