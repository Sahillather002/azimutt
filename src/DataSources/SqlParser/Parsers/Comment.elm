module DataSources.SqlParser.Parsers.Comment exposing (CommentOnColumn, CommentOnTable, SqlComment, parseColumnComment, parseTableComment)

import DataSources.SqlParser.Utils.Helpers exposing (buildColumnName, buildRawSql, buildSchemaName, buildSqlLine, buildTableName)
import DataSources.SqlParser.Utils.Types exposing (ParseError, SqlColumnName, SqlSchemaName, SqlStatement, SqlTableName)
import Libs.Regex as R


type alias CommentOnTable =
    { schema : Maybe SqlSchemaName, table : SqlTableName, comment : SqlComment }


type alias CommentOnColumn =
    { schema : Maybe SqlSchemaName, table : SqlTableName, column : SqlColumnName, comment : SqlComment }


type alias SqlComment =
    String


parseTableComment : SqlStatement -> Result (List ParseError) CommentOnTable
parseTableComment statement =
    case statement |> buildSqlLine |> R.matches "^COMMENT ON TABLE\\s+(?:(?<schema>[^ .]+)\\.)?(?<table>[^ .]+)\\s+IS\\s+'(?<comment>(?:[^']|'')+)';$" of
        schema :: (Just table) :: (Just comment) :: [] ->
            Ok { schema = schema |> Maybe.map buildSchemaName, table = table |> buildTableName, comment = comment |> String.replace "''" "'" }

        _ ->
            Err [ "Can't parse table comment: '" ++ buildRawSql statement ++ "'" ]


parseColumnComment : SqlStatement -> Result (List ParseError) CommentOnColumn
parseColumnComment statement =
    case statement |> buildSqlLine |> R.matches "^COMMENT ON COLUMN\\s+(?:(?<schema>[^ .]+)\\.)?(?<table>[^ .]+)\\.(?<column>[^ .]+)\\s+IS\\s+'(?<comment>(?:[^']|'')+)';$" of
        schema :: (Just table) :: (Just column) :: (Just comment) :: [] ->
            Ok { schema = schema |> Maybe.map buildSchemaName, table = table |> buildTableName, column = column |> buildColumnName, comment = comment |> String.replace "''" "'" }

        _ ->
            Err [ "Can't parse column comment: '" ++ buildRawSql statement ++ "'" ]
