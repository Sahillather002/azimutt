module TestHelpers.OrganizationFuzzers exposing (..)

import Fuzz exposing (Fuzzer)
import Libs.Fuzz as Fuzz
import Models.Organization exposing (Organization)
import Models.OrganizationId exposing (OrganizationId)
import Models.OrganizationName exposing (OrganizationName)
import Models.OrganizationSlug exposing (OrganizationSlug)
import Models.Plan exposing (Plan)
import TestHelpers.CleverCloudFuzzers exposing (cleverCloudResource)
import TestHelpers.Fuzzers exposing (identifier, intPosSmall, stringSmall, uuid)
import TestHelpers.HerokuFuzzers exposing (herokuResource)


organization : Fuzzer Organization
organization =
    Fuzz.map8 Organization organizationId organizationSlug organizationName plan logo (Fuzz.maybe description) (Fuzz.maybe cleverCloudResource) (Fuzz.maybe herokuResource)


organizationId : Fuzzer OrganizationId
organizationId =
    uuid


organizationSlug : Fuzzer OrganizationSlug
organizationSlug =
    identifier


organizationName : Fuzzer OrganizationName
organizationName =
    identifier


plan : Fuzzer Plan
plan =
    Fuzz.map16 Plan planId planName Fuzz.bool Fuzz.bool (Fuzz.maybe intPosSmall) Fuzz.bool Fuzz.bool stringSmall Fuzz.bool (Fuzz.maybe intPosSmall) (Fuzz.maybe intPosSmall) (Fuzz.maybe intPosSmall) (Fuzz.maybe intPosSmall) (Fuzz.maybe intPosSmall) Fuzz.bool Fuzz.int


planId : Fuzzer String
planId =
    Fuzz.oneOf ([ "free", "pro" ] |> List.map Fuzz.constant)


planName : Fuzzer String
planName =
    Fuzz.oneOf ([ "Free plan", "Pro plan" ] |> List.map Fuzz.constant)


logo : Fuzzer String
logo =
    stringSmall


description : Fuzzer String
description =
    stringSmall
