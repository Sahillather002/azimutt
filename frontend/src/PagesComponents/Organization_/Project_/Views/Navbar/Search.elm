module PagesComponents.Organization_.Project_.Views.Navbar.Search exposing (viewNavbarSearch)

import Components.Atoms.Icon as Icon exposing (Icon(..))
import Components.Atoms.Icons as Icons
import Components.Molecules.ContextMenu as ContextMenu exposing (Direction(..))
import Components.Molecules.Dropdown as Dropdown
import Conf
import Dict exposing (Dict)
import Html exposing (Attribute, Html, button, div, input, kbd, label, li, span, text, ul)
import Html.Attributes exposing (autocomplete, class, for, id, name, placeholder, tabindex, type_, value)
import Html.Events exposing (onBlur, onFocus, onInput, onMouseDown)
import Libs.Bool as B
import Libs.Html.Attributes exposing (css, role)
import Libs.Maybe as Maybe
import Libs.Models.HtmlId exposing (HtmlId)
import Libs.Models.Notes exposing (Notes)
import Libs.String exposing (pluralizeD)
import Libs.Tailwind exposing (TwClass, focus, lg, sm)
import Models.Project.ColumnPath as ColumnPath
import Models.Project.Metadata as Metadata exposing (Metadata)
import Models.Project.SchemaName exposing (SchemaName)
import Models.Project.TableId as TableId exposing (TableId)
import Models.Project.TableMeta exposing (TableMeta)
import PagesComponents.Organization_.Project_.Components.DetailsSidebar as DetailsSidebar
import PagesComponents.Organization_.Project_.Models exposing (Msg(..), SearchModel, confirm)
import PagesComponents.Organization_.Project_.Models.Erd as Erd exposing (Erd)
import PagesComponents.Organization_.Project_.Models.ErdColumn exposing (ErdColumn)
import PagesComponents.Organization_.Project_.Models.ErdLayout exposing (ErdLayout)
import PagesComponents.Organization_.Project_.Models.ErdRelation exposing (ErdRelation)
import PagesComponents.Organization_.Project_.Models.ErdTable as ErdTable exposing (ErdTable)
import PagesComponents.Organization_.Project_.Models.ErdTableLayout exposing (ErdTableLayout)
import Services.Search as Search
import Set exposing (Set)
import Simple.Fuzzy


viewNavbarSearch : Erd -> SearchModel -> HtmlId -> HtmlId -> Html Msg
viewNavbarSearch erd search htmlId openedDropdown =
    let
        defaultSchema : SchemaName
        defaultSchema =
            erd.settings.defaultSchema

        shownTables : List ErdTableLayout
        shownTables =
            erd |> Erd.currentLayout |> .tables

        shown : Set TableId
        shown =
            shownTables |> List.map .id |> Set.fromList
    in
    div [ class "ml-6 print:hidden" ]
        [ div [ css [ "max-w-lg w-full", lg [ "max-w-xs" ] ] ]
            [ label [ for htmlId, class "sr-only" ] [ text "Search" ]
            , Dropdown.dropdown { id = htmlId, direction = BottomRight, isOpen = openedDropdown == htmlId }
                (\m ->
                    div []
                        [ div [ class "pointer-events-none absolute inset-y-0 left-0 pl-3 flex items-center" ] [ Icon.solid Search "text-primary-200" ]
                        , input
                            [ type_ "search"
                            , name "search"
                            , id m.id
                            , placeholder "Search"
                            , autocomplete False
                            , value search.text
                            , onInput SearchUpdated
                            , onFocus (DropdownOpen m.id)
                            , onBlur DropdownClose
                            , css [ "block w-full pl-10 pr-3 py-2 border border-transparent rounded-md leading-5 bg-primary-500 text-primary-100 placeholder-primary-200", focus [ "outline-none bg-white border-white ring-white text-primary-900 placeholder-primary-400" ], sm [ "text-sm" ] ]
                            ]
                            []
                        , Conf.hotkeys
                            |> Dict.get "search-open"
                            |> Maybe.andThen List.head
                            |> Maybe.mapOrElse
                                (\h ->
                                    div [ class "absolute inset-y-0 right-0 flex py-1.5 pr-1.5" ]
                                        [ kbd [ class "inline-flex items-center border border-primary-300 rounded px-2 text-sm font-sans font-medium text-primary-300" ]
                                            [ text h.key ]
                                        ]
                                )
                                (div [] [])
                        ]
                )
                (\m ->
                    if search.text == "" then
                        div []
                            [ span [ role "menuitem", tabindex -1, css [ "flex w-full items-center", ContextMenu.itemDisabledStyles ] ]
                                [ text "Search into tables (", Icon.solid Icons.table "", text "), columns (", Icon.solid Icons.column "", text ") and relations (", Icon.solid Icons.columns.foreignKey "", text "), use '?' for advanced search" ]
                            , button
                                [ type_ "button"
                                , onMouseDown (B.cond (Dict.size erd.tables < Conf.constants.manyTablesLimit) (ShowAllTables "search") (confirm "Show all tables" (text ("You are about to show " ++ (erd.tables |> pluralizeD "table") ++ ". That's a lot. It may slow down your browser and make Azimutt unresponsive. Continue?")) (ShowAllTables "search")))
                                , role "menuitem"
                                , tabindex -1
                                , css [ "flex w-full items-center", focus [ "outline-none" ], ContextMenu.itemStyles ]
                                ]
                                [ text ("Show all tables (" ++ (erd.tables |> Dict.size |> String.fromInt) ++ ")") ]
                            , button [ type_ "button", onMouseDown (DetailsSidebarMsg DetailsSidebar.Toggle), role "menuitem", tabindex -1, css [ "flex w-full items-center", focus [ "outline-none" ], ContextMenu.itemStyles ] ]
                                [ text "Browse table list" ]
                            , let
                                topTables : List ErdTable
                                topTables =
                                    erd.tables |> Dict.values |> List.sortBy (ErdTable.rank >> negate) |> List.filter (\t -> shown |> Set.member t.id |> not) |> List.take 15
                              in
                              if topTables |> List.isEmpty then
                                div [] []

                              else
                                div [ class "border-t" ]
                                    (span [ role "menuitem", tabindex -1, css [ "flex w-full items-center py-2 px-4 text-sm text-gray-700" ] ] [ text "Or check other interesting tables:" ]
                                        :: (topTables |> List.map (\t -> FoundTable t) |> List.indexedMap (viewSearchResult m.id defaultSchema shown -1))
                                    )
                            ]

                    else if search.text == "?" then
                        div []
                            [ div [ role "menuitem", tabindex -1, css [ "flex w-full items-center", ContextMenu.itemDisabledStyles ] ]
                                [ text "Azimutt has some special search patterns:"
                                ]
                            , div [ role "menuitem", tabindex -1, css [ "flex w-full items-center", ContextMenu.itemDisabledStyles ] ]
                                [ ul [ class "list-disc list-inside" ]
                                    [ li [] [ text "'!layout' for tables not present in any layout" ]
                                    , li [] [ text "'!notes' for tables and columns without notes" ]
                                    , li [] [ text "'notes:bla bla' for tables and columns with 'bla bla' in notes" ]
                                    , li [] [ text "'!tag' for tables and columns without any tag" ]
                                    , li [] [ text "'tag:name' for tables and columns with 'name' tag" ]
                                    ]
                                ]
                            ]

                    else
                        performSearch erd (String.toLower search.text)
                            |> (\results ->
                                    if results |> List.isEmpty then
                                        div []
                                            [ span [ role "menuitem", tabindex -1, css [ "flex w-full items-center", ContextMenu.itemDisabledStyles ] ]
                                                [ text "No result :(" ]
                                            ]

                                    else
                                        div [ class "max-h-192 overflow-y-auto" ]
                                            (results |> List.indexedMap (viewSearchResult m.id defaultSchema shown (search.active |> modBy (results |> List.length))))
                               )
                )
            ]
        ]


type SearchResult
    = FoundTable ErdTable
    | FoundColumn ErdTable ErdColumn
    | FoundRelation ErdRelation


viewSearchResult : HtmlId -> SchemaName -> Set TableId -> Int -> Int -> SearchResult -> Html Msg
viewSearchResult searchId defaultSchema shown active index res =
    let
        viewItem : String -> TableId -> Icon -> List (Html Msg) -> Bool -> Html Msg
        viewItem =
            \kind table icon content disabled ->
                let
                    commonAttrs : List (Attribute Msg)
                    commonAttrs =
                        [ type_ "button", onMouseDown (SearchClicked kind table), role "menuitem", tabindex -1 ] ++ B.cond (active == index) [ id (searchId ++ "-active-item") ] []

                    commonStyles : TwClass
                    commonStyles =
                        "flex w-full items-center"
                in
                if disabled then
                    button (commonAttrs ++ [ css [ commonStyles, B.cond (active == index) ContextMenu.itemDisabledActiveStyles ContextMenu.itemDisabledStyles ] ])
                        ([ Icon.solid icon "mr-3" ] ++ content)

                else
                    button (commonAttrs ++ [ css [ commonStyles, focus [ "outline-none" ], B.cond (active == index) ContextMenu.itemActiveStyles ContextMenu.itemStyles ] ])
                        ([ Icon.solid icon "mr-3" ] ++ content)
    in
    case res of
        FoundTable table ->
            viewItem "table" table.id Icons.table [ text (TableId.show defaultSchema table.id) ] (shown |> Set.member table.id)

        FoundColumn table column ->
            viewItem "column" table.id Icons.column [ span [ class "opacity-50" ] [ text (TableId.show defaultSchema table.id ++ ".") ], text (ColumnPath.show column.path) ] (shown |> Set.member table.id)

        FoundRelation relation ->
            if shown |> Set.member relation.src.table |> not then
                viewItem "relation" relation.src.table Icons.columns.foreignKey [ text relation.name ] False

            else if shown |> Set.member relation.ref.table |> not then
                viewItem "relation" relation.ref.table Icons.columns.foreignKey [ text relation.name ] False

            else
                viewItem "relation" relation.src.table Icons.columns.foreignKey [ text relation.name ] True


filterColumns : List a -> Int -> Metadata -> List ErdTable -> (Maybe TableMeta -> ErdColumn -> Bool) -> List SearchResult
filterColumns tableResults maxResults metadata tables filter =
    if (tableResults |> List.length) < maxResults then
        tables |> List.concatMap (\t -> (metadata |> Dict.get t.id) |> (\m -> (t.columns |> Dict.values) |> List.filter (filter m) |> List.map (FoundColumn t)))

    else
        []


performSearch : Erd -> String -> List SearchResult
performSearch erd lQuery =
    let
        maxResults : Int
        maxResults =
            30

        tables : List ErdTable
        tables =
            erd.tables
                |> Dict.values
                |> List.sortBy (\t -> t.id |> TableId.toString)
    in
    if lQuery == Search.notInLayouts then
        tables |> List.filter (Search.tableNotInLayouts erd.layouts) |> List.map FoundTable |> List.take maxResults

    else if lQuery == Search.noNotes then
        let
            tableResults : List SearchResult
            tableResults =
                tables |> List.filter (Search.tableNoNotes erd.metadata) |> List.map FoundTable

            columnResults : List SearchResult
            columnResults =
                filterColumns tableResults maxResults erd.metadata tables Search.columnNoNotes
        in
        (tableResults ++ columnResults) |> List.take maxResults

    else if lQuery |> String.startsWith Search.hasNotes then
        let
            text : String
            text =
                lQuery |> String.dropLeft 6

            tableResults : List SearchResult
            tableResults =
                tables |> List.filter (Search.tableHasNotes text erd.metadata) |> List.map FoundTable

            columnResults : List SearchResult
            columnResults =
                filterColumns tableResults maxResults erd.metadata tables (Search.columnHasNotes text)
        in
        (tableResults ++ columnResults) |> List.take maxResults

    else if lQuery == Search.noTag then
        let
            tableResults : List SearchResult
            tableResults =
                tables |> List.filter (Search.tableNoTag erd.metadata) |> List.map FoundTable

            columnResults : List SearchResult
            columnResults =
                filterColumns tableResults maxResults erd.metadata tables Search.columnNoTag
        in
        (tableResults ++ columnResults) |> List.take maxResults

    else if lQuery |> String.startsWith Search.hasTag then
        let
            tag : String
            tag =
                lQuery |> String.dropLeft 4

            tableResults : List SearchResult
            tableResults =
                tables |> List.filter (Search.tableHasTag tag erd.metadata) |> List.map FoundTable

            columnResults : List SearchResult
            columnResults =
                filterColumns tableResults maxResults erd.metadata tables (Search.columnHasTag tag)
        in
        (tableResults ++ columnResults) |> List.take maxResults

    else
        let
            tableResults : List ( Float, SearchResult )
            tableResults =
                tables |> List.filterMap (\t -> t |> tableMatch lQuery (erd.metadata |> Metadata.getNotes t.id Nothing))

            columnResults : List ( Float, SearchResult )
            columnResults =
                if (tableResults |> List.length) < maxResults then
                    tables
                        |> List.concatMap
                            (\table ->
                                (erd.metadata |> Dict.get table.id)
                                    |> (\n ->
                                            (table.columns |> Dict.values)
                                                |> List.filterMap (\c -> c |> columnMatch lQuery (n |> Maybe.andThen (.columns >> ColumnPath.get c.path) |> Maybe.andThen .notes) table)
                                       )
                            )

                else
                    []

            relationResults : List ( Float, SearchResult )
            relationResults =
                if ((tableResults |> List.length) + (columnResults |> List.length)) < maxResults then
                    erd.relations |> List.filterMap (relationMatch lQuery)

                else
                    []
        in
        (tableResults ++ columnResults ++ relationResults) |> List.sortBy (\( r, _ ) -> negate r) |> List.take maxResults |> List.map Tuple.second


tableMatch : String -> Maybe Notes -> ErdTable -> Maybe ( Float, SearchResult )
tableMatch lQuery notes table =
    if String.toLower table.name == lQuery then
        Just ( 9, FoundTable table )

    else if table.name |> String.toLower |> String.startsWith lQuery then
        Just ( 8 + shortBonus table.name, FoundTable table )

    else if table.name |> match lQuery then
        Just ( 7 + shortBonus table.name, FoundTable table )

    else if table.name |> fuzzy lQuery then
        Just ( 6 + shortBonus table.name, FoundTable table )

    else if
        (table.comment |> Maybe.any (.text >> match lQuery))
            || (notes |> Maybe.any (match lQuery))
            || (table.primaryKey |> Maybe.andThen .name |> Maybe.any (match lQuery))
            || (table.uniques |> List.any (\u -> (u.name |> match lQuery) || (u.definition |> Maybe.any (match lQuery))))
            || (table.indexes |> List.any (\i -> (i.name |> match lQuery) || (i.definition |> Maybe.any (match lQuery))))
            || (table.checks |> List.any (\c -> (c.name |> match lQuery) || (c.predicate |> Maybe.any (match lQuery))))
    then
        Just ( 5 + shortBonus table.name, FoundTable table )

    else if
        (table.comment |> Maybe.any (.text >> fuzzy lQuery))
            || (notes |> Maybe.any (fuzzy lQuery))
    then
        Just ( 4 + shortBonus table.name, FoundTable table )

    else
        Nothing


columnMatch : String -> Maybe Notes -> ErdTable -> ErdColumn -> Maybe ( Float, SearchResult )
columnMatch lQuery notes table column =
    if (column.path |> ColumnPath.toString |> String.toLower) == lQuery then
        Just ( 0.9, FoundColumn table column )

    else if column.path |> ColumnPath.toString |> String.toLower |> String.startsWith lQuery then
        Just ( 0.8, FoundColumn table column )

    else if column.path |> ColumnPath.toString |> match lQuery then
        Just ( 0.7, FoundColumn table column )

    else if column.path |> ColumnPath.toString |> fuzzy lQuery then
        Just ( 0.6, FoundColumn table column )

    else if
        (column.comment |> Maybe.any (.text >> match lQuery))
            || (notes |> Maybe.any (match lQuery))
            || (column.kind |> match lQuery)
            || (column.default |> Maybe.any (match lQuery))
    then
        Just ( 0.5, FoundColumn table column )

    else if
        (column.comment |> Maybe.any (.text >> fuzzy lQuery))
            || (notes |> Maybe.any (fuzzy lQuery))
    then
        Just ( 0.4, FoundColumn table column )

    else
        Nothing


relationMatch : String -> ErdRelation -> Maybe ( Float, SearchResult )
relationMatch lQuery relation =
    if String.toLower relation.name == lQuery then
        Just ( 0.09, FoundRelation relation )

    else if relation.name |> String.toLower |> String.startsWith lQuery then
        Just ( 0.08, FoundRelation relation )

    else if relation.name |> match lQuery then
        Just ( 0.07, FoundRelation relation )

    else if relation.name |> fuzzy lQuery then
        Just ( 0.06, FoundRelation relation )

    else if
        (relation.src.column |> ColumnPath.toString |> match lQuery)
            || (relation.ref.column |> ColumnPath.toString |> match lQuery)
            || (relation.src.table |> Tuple.second |> match lQuery)
            || (relation.ref.table |> Tuple.second |> match lQuery)
    then
        Just ( 0.05, FoundRelation relation )

    else
        Nothing


match : String -> String -> Bool
match lQuery text =
    text |> String.toLower |> String.contains lQuery


fuzzy : String -> String -> Bool
fuzzy lQuery text =
    text |> Simple.Fuzzy.match lQuery


shortBonus : String -> Float
shortBonus text =
    1 / toFloat (String.length text)
