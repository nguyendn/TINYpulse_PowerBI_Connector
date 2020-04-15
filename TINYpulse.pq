[Version = "0.0.1"]
section TINYpulse;

//
// Definition
//

// Data Source Kind description
TINYpulse = [
    Authentication = [
        Key = []
        // UsernamePassword = [],
        // Windows = [],
        //Implicit = []
        //Anonymous = []
    ],
    Label = Extension.LoadString("DataSourceLabel")
];

// Data Source UI publishing description
TINYpulse.Publish = [
    Beta = true,
    Category = "Online Services",
    ButtonText = { Extension.LoadString("ButtonTitle"), Extension.LoadString("ButtonHelp") },
    LearnMoreUrl = "https://api-docs.tinypulse.com/doc/api",
    SourceImage = TINYpulse.Icons,
    SourceTypeImage = TINYpulse.Icons
];

TINYpulse.Icons = [
    Icon16 = { Extension.Contents("TINYpulse16.png"), Extension.Contents("TINYpulse20.png"), Extension.Contents("TINYpulse24.png"), Extension.Contents("TINYpulse32.png") },
    Icon32 = { Extension.Contents("TINYpulse32.png"), Extension.Contents("TINYpulse40.png"), Extension.Contents("TINYpulse48.png"), Extension.Contents("TINYpulse64.png") }
];

//
// Interface
// 

[DataSource.Kind="TINYpulse", Publish="TINYpulse.Publish"]
shared TINYpulse.Report = Value.ReplaceType(EngageData, Interface);

Interface = type function (
                #"Report" as (type text meta [
                    Documentation.FieldCaption = "Report",
                    Documentation.FieldDescription = "Select which report you would like returned.",
                    Documentation.AllowedValues = { "Surveys", "Responses", "Suggestions", "Cheers", "Onboard/Responses", "Segments", "Filters"}
                ]))
                as table meta [
                    Documentation.Name = "Connect to TINYpulse"
                ];

EngageData = (#"Report" as text) as table => ExpandDocumented( GetAllPagesByNextLink(Endpoint(#"Report")), #"Report");

//
// Implementation
// 

BaseUrl = "https://api.tinypulse.com/pulse/v1/";
Endpoint = (report) => BaseUrl&Text.Lower(report);

GetPage = (url as text) as table =>
    let
        apiKey = Extension.CurrentCredential()[Key],
        source = Json.Document(Web.Contents(url, [Headers=[AccessToken=apiKey]])),        
        nextLink = try source[links][next] otherwise null,
        data = Table.FromRecords(source[data])
    in
        data meta [NextLink = nextLink];

GetAllPagesByNextLink = (url as text) as table =>
    Table.GenerateByPage((previous) => 
        let
            // if previous is null, then this is our first page of data
            nextLink = if (previous = null) then url else Value.Metadata(previous)[NextLink]?,
            // if NextLink was set to null by the previous call, we know we have no more data
            page = if (nextLink <> null) then GetPage(nextLink) else null
        in
            page
    );

//
// Helper
// 

ExpandDocumented = (response, report) => if report = "Surveys" then ExpandedSurveys(response)
                                 else if report = "Responses" then ExpandedResponses(response)
                                 else if report = "Cheers" then ExpandedCheers(response)
                                 else if report = "Onboard/Responses" then ExpandedOnboardReponses(response)
                                 else if report = "Suggestions" then ExpandedSuggestions(response)
                                 else if report = "Filters" then ExpandedFilters(response)
                                 else ExpandedSegments(response);

ExpandedSurveys = (response as table) as table =>
                    let
                         expandedTable = Table.ExpandRecordColumn(response, "attributes", 
                                            {"date_asked", "organization_name", "date_closed", "survey_type", "question_text", "question_type", 
                                             "category_name", "responses_count", "receivers_count", "response_rate", "suggestions_count", "cheers_count", "pm_count"})
                    in
                         Table.RemoveColumns(expandedTable, "links");


ExpandedResponses = (response as table) as table =>
                    let
                         expandedTable = Table.ExpandRecordColumn( response, "attributes", 
                                            {"score", "choices", "response_text", "survey_id", "submitted_at", "question_type", "question_text", "segment", "organization_name"})
                    in
                         Table.RemoveColumns(expandedTable, {"relationships", "choices"});

ExpandedSuggestions = (response as table) as table =>
                    let
                         expandedTable = Table.ExpandRecordColumn( response, "attributes", 
                                            {"submitted_at", "suggestion", "public", "upvotes"})
                    in
                         Table.RemoveColumns(expandedTable, "relationships");

ExpandedOnboardReponses = (response as table) as table =>
                    let
                         expandedTable = Table.ExpandRecordColumn( response, "attributes", 
                                            {"score", "response_text", "submitted_at", "question_type", "question_text", "email", "segment", "organization_name", "week"})
                    in
                       Table.RemoveColumns(expandedTable, "relationships");

ExpandedSegments = (response as table) as table => Table.ExpandRecordColumn( response, "attributes", {"name", "receiver_count"});

ExpandedFilters = (response as table) as table => Table.ExpandRecordColumn( response, "attributes", {"name", "receiver_count"});

ExpandedCheers = (response as table) as table =>
                    let
                         expandedTable = Table.ExpandRecordColumn( response, "attributes",
                                            {"praise", "created_at", "sender_name", "sender_email", "receiver_name", "receiver_email", "sender_segment", "receiver_segment"})
                    in
                         Table.RemoveColumns(expandedTable, "relationships");

// https://docs.microsoft.com/en-us/power-query/helperfunctions
// The getNextPage function takes a single argument and is expected to return a nullable table
Table.GenerateByPage = (getNextPage as function) as table =>
    let        
        listOfPages = List.Generate(
            () => getNextPage(null),            // get the first page of data
            (lastPage) => lastPage <> null,     // stop when the function returns null
            (lastPage) => getNextPage(lastPage) // pass the previous page to the next function call
        ),
        // concatenate the pages together
        tableOfPages = Table.FromList(listOfPages, Splitter.SplitByNothing(), {"Column1"}),
        firstRow = tableOfPages{0}?
    in
        // if we didn't get back any pages of data, return an empty table
        // otherwise set the table type based on the columns of the first page
        if (firstRow = null) then
            Table.FromRows({})
        else        
            Value.ReplaceType(
                Table.ExpandTableColumn(tableOfPages, "Column1", Table.ColumnNames(firstRow[Column1])),
                Value.Type(firstRow[Column1])
            );