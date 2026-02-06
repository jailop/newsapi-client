import std/[httpclient, net, uri, strutils, strformat, asyncfutures,
  asyncdispatch, typetraits, times, json]

type

  ## NewsCategory defines available topic categories for filtering news
  ## content. Each enum value maps to the corresponding API string value
  ## accepted by NewsAPI endpoints. Categories enable topical filtering in
  ## headlines and sources requests.
  NewsCategory* = enum
    ncBusiness = "business",
    ncEntertainment = "entertainment",
    ncGeneral = "general",
    ncHealth = "health",
    ncScience = "science",
    ncSports = "sports",
    ncTechnology = "technology"

  ## HeadLinesRequest retrieves breaking news and current top headlines from
  ## the NewsAPI service. The type requires either a country code or a list
  ## of source identifiers. The country field accepts two-letter ISO 3166-1
  ## codes, while sources expects a sequence of source identifier strings.
  ## All requests must include an apiKey field containing the API
  ## authentication token. Pagination is controlled through pageSize (1 to
  ## 100) and page (starting from 1) fields.
  HeadLinesRequest* = object
    apiKey*: string
    country*: string
    category*: NewsCategory
    sources*: seq[string] = @[]
    pageSize*: int = 20
    page*: int = 1

  ## NewsSourceId identifies the outlet that published an article. The id
  ## field contains the NewsAPI source identifier string, while name
  ## provides a human-readable outlet name. This type appears in the source
  ## field of NewsArticle objects.
  NewsSourceId* = object
    id*: string
    name*: string

  ## NewsArticle represents a single news article retrieved from the
  ## NewsAPI service. Fields include source identification, authorship,
  ## title, description, urls for the article and associated image, ISO
  ## 8601 publication timestamp, and truncated content text. Fields may
  ## contain empty strings when data is unavailable from the source.
  NewsArticle* = object
    source*: NewsSourceId
    author*: string
    title*: string
    description*: string
    url*: string
    urlToImage*: string
    publishedAt*: string
    content*: string

  ## NewsResponse contains the deserialized API response from headlines and
  ## everything endpoint requests. The status field indicates success ("ok")
  ## or error ("error"). The totalResults field contains the count of
  ## available articles matching the query parameters. The articles sequence
  ## contains the retrieved NewsArticle objects for the requested page.
  NewsResponse* = object
    status*: string
    totalResults*: int
    articles*: seq[NewsArticle]

  ## SourcesRequest discovers available news outlets from the NewsAPI
  ## service. Unlike headline requests, all fields are optional, allowing
  ## retrieval of the complete source catalog. The category, language, and
  ## country fields filter the result set to sources matching specified
  ## criteria. Language uses two-letter ISO 639-1 codes.
  SourcesRequest* = object
    apiKey*: string
    category*: NewsCategory
    language*: string
    country*: string

  ## NewsSource describes a news outlet with metadata about its coverage and
  ## characteristics. Fields include a unique identifier, human-readable
  ## name, description of coverage, website url, topical category, language
  ## code, and country code. These objects are returned by the sources
  ## endpoint and referenced in article source fields.
  NewsSource* = object
    id*: string
    name*: string
    description*: string
    url*: string
    category*: NewsCategory
    language*: string
    country*: string

  ## SourcesResponse contains the deserialized API response from sources
  ## endpoint requests. The status field indicates success or failure. The
  ## sources sequence contains NewsSource objects describing each available
  ## news outlet matching the filter criteria.
  SourcesResponse* = object
    status*: string
    sources*: seq[NewsSource]

  ## ErrorCode enumerates the possible error conditions returned by the
  ## NewsAPI service. Values correspond to API error codes for
  ## authentication failures, rate limiting, parameter validation, and
  ## service errors. These codes appear in ErrorResponse objects when
  ## requests fail.
  ErrorCode = enum
    ecApiKeyDisabled = "apiKeyDisabled",
    ecApiKeyExhausted = "apiKeyExhausted",
    ecApiKeyInvalid = "apiKeyInvalid",
    ecApiKeyMissing = "apiKeyMissing",
    ecParameterInvalid = "parameterInvalid",
    ecParametersMissing = "parametersMissing",
    ecRateLimited = "rateLimited",
    ecSourcesTooMany = "sourcesTooMany",
    ecSourceDoesNotExist = "sourceDoesNotExist",
    ecUnexpectedError = "unexpectedError"

  ## ErrorResponse contains error information returned by the NewsAPI
  ## service when requests fail. The status field contains "error", the code
  ## field contains an ErrorCode value identifying the failure type, and the
  ## message field provides a human-readable diagnostic description.
  ErrorResponse* = object
    status*: string
    code*: ErrorCode
    message*: string

  ## SearchInCategory specifies which article fields should be searched when
  ## performing comprehensive searches with EverythingRequest. Values limit
  ## search matching to title, description, or full content fields. Multiple
  ## values can be combined to search across multiple fields simultaneously.
  SearchInCategory* = enum
    sicTitle = "title",
    sicDescription = "description",
    sicContent = "content"

  ## SortByCategory controls the ordering of search results in
  ## EverythingRequest queries. The sbRelevancy value orders by best match
  ## to the search query, sbPopularity orders by most-shared articles, and
  ## sbPublishedAt provides chronological ordering by publication timestamp.
  SortByCategory* = enum
    sbRelevancy = "relevancy",
    sbPopularity = "popularity",
    sbPublishedAt = "publishedAt"

  ## EverythingRequest performs comprehensive searches across all articles
  ## in the NewsAPI index. The q field containing the search query is
  ## mandatory. The searchIn field accepts a sequence of SearchInCategory
  ## values to limit where matches occur. The sources, domains, and
  ## excludeDomains fields constrain results by outlet or web domain.
  ## Temporal bounds are specified through from and to fields as ISO 8601
  ## date strings (YYYY-MM-DD). The sortBy field controls result ordering.
  ## As with other requests, pagination and authentication fields are
  ## included.
  EverythingRequest* = object
    apiKey*: string
    q*: string
    searchIn*: seq[SearchInCategory] = @[]
    sources*: seq[string] = @[]
    domains*: seq[string] = @[]
    excludeDomains*: seq[string] = @[]
    `from`*: string = ""
    `to`*: string = ""
    language*: string = ""
    sortBy*: SortByCategory = sbPublishedAt
    pageSize*: int = 100
    page*: int = 1

const baseUrl = "https://newsapi.org/v2"

## request constructs and executes an HTTP GET request to the specified
## NewsAPI endpoint with the given query parameters. The procedure returns
## the response body as a string. SSL certificate verification is disabled
## for compatibility. Network errors and non-200 HTTP status codes raise
## exceptions with diagnostic messages. This is an internal procedure used
## by the pull method implementations.
proc request*(endpoint: string, params: seq[(string, string)]):
  Future[string] {.async.} =
  let client = newAsyncHttpClient(sslContext = newContext(
    verifyMode = CVerifyNone))
  try:
    let url = baseUrl & endpoint & "?" & encodeQuery(toOpenArray(params, 0, params.high))
    when defined(debug):
      echo "Requesting: ", url
    let response = await client.get(url)
    let body = await response.body()
    if response.status != "200 OK":
      raise newException(Exception,
        fmt"Error pulling data from {url}: {response.status}")
    return body
  except HttpRequestError as e:
    raise newException(Exception, fmt"Connection error: " & e.msg)

## validateDate checks that the given date string conforms to expected ISO
## 8601 formats. The procedure accepts both date-only (YYYY-MM-DD) and full
## datetime formats with timezone information. Empty strings are treated as
## valid to support optional date fields. Invalid formats raise ValueError
## exceptions with diagnostic messages including the field name and expected
## format.
proc validateDate(dateStr: string, fieldName: string) =
  if dateStr.len == 0:
    return
  if dateStr.contains('T'):
    try:
      discard parse(dateStr, "yyyy-MM-dd'T'HH:mm:ss'Z'")
      return
    except:
      try:
        discard parse(dateStr, "yyyy-MM-dd'T'HH:mm:sszzz")
        return
      except:
        raise newException(ValueError,
          fmt"Invalid datetime format for '{fieldName}': {dateStr}. " &
          fmt"Expected ISO 8601 format (e.g., 2024-01-01T00:00:00Z)")
  else:
    try:
      discard parse(dateStr, "yyyy-MM-dd")
      return
    except:
      raise newException(ValueError,
        fmt"Invalid date format for '{fieldName}': {dateStr}. " &
        fmt"Expected YYYY-MM-DD format")

## parseCategory converts a string to a NewsCategory enum value. The
## procedure accepts case-insensitive category names matching the enum
## string values (business, entertainment, general, health, science, sports,
## technology). Invalid category names raise ValueError exceptions listing
## the valid options.
proc parseCategory*(s: string): NewsCategory =
  try:
    result = parseEnum[NewsCategory](s.toLowerAscii())
  except ValueError:
    raise newException(ValueError, "Invalid category: " & s &
      ". Valid options: business, entertainment, general, health, " &
      "science, sports, technology")

## parseSortBy converts a string to a SortByCategory enum value. The
## procedure accepts case-insensitive sort option names with or without
## hyphens (relevancy, popularity, publishedAt). Invalid sort options raise
## ValueError exceptions listing the valid choices.
proc parseSortBy*(s: string): SortByCategory =
  let normalized = s.toLowerAscii().replace("-", "")
  try:
    result = parseEnum[SortByCategory](normalized)
  except ValueError:
    raise newException(ValueError, "Invalid sort option: " & s &
      ". Valid options: relevancy, popularity, publishedAt")

## parseSearchIn converts a comma-separated string to a sequence of
## SearchInCategory enum values. The procedure accepts case-insensitive
## field names (title, description, content), strips whitespace, and returns
## the parsed sequence. Invalid field names raise ValueError exceptions
## listing valid options.
proc parseSearchIn*(s: string): seq[SearchInCategory] =
  result = @[]
  for part in s.split(','):
    let normalized = part.strip().toLowerAscii()
    try:
      result.add(parseEnum[SearchInCategory](normalized))
    except ValueError:
      raise newException(ValueError, "Invalid search-in value: " & part &
        ". Valid options: title, description, content")

## validateAndFormatDate checks that a date string conforms to ISO 8601
## formats and returns the validated string unchanged. The procedure accepts
## both date-only (YYYY-MM-DD) and full datetime formats with timezone
## information. Empty strings are returned as-is to support optional date
## fields. Invalid formats raise ValueError exceptions with format guidance.
proc validateAndFormatDate*(dateStr: string): string =
  if dateStr.len == 0:
    return ""
  
  if dateStr.contains('T'):
    try:
      discard parse(dateStr, "yyyy-MM-dd'T'HH:mm:ss'Z'")
      return dateStr
    except:
      try:
        discard parse(dateStr, "yyyy-MM-dd'T'HH:mm:sszzz")
        return dateStr
      except:
        raise newException(ValueError, 
          "Invalid datetime format. Use ISO 8601 (e.g., 2024-01-01T00:00:00Z)")
  else:
    try:
      discard parse(dateStr, "yyyy-MM-dd")
      return dateStr
    except:
      raise newException(ValueError, "Invalid date format. Use YYYY-MM-DD")

proc toQueryParams*[T](obj: T): seq[(string, string)] =
  result = @[]
  for name, value in obj.fieldPairs:
    when value is string:
      if value.len > 0:
        if name == "from" or name == "to":
          validateDate(value, name)
        result.add((name, value))
    elif value is int or value is int64:
      if value > 0:
        result.add((name, $value))
    elif value is enum:
      result.add((name, $value))
    elif value is seq:
      when value is seq[string]:
        if value.len > 0:
          result.add((name, value.join(",")))
      elif value is seq[SearchInCategory]:
        if value.len > 0:
          var items: seq[string] = @[]
          for item in value:
            items.add($item)
          result.add((name, items.join(",")))

proc pull*(req: HeadLinesRequest): Future[NewsResponse] {.async.} =
  let params = toQueryParams(req)
  let endpoint = "/top-headlines"
  var content: string
  try:
    content = await request(endpoint, params)
  except Exception as e:
    raise newException(Exception, "Failed to fetch data: " & e.msg)
  try:
    return content.parseJson().to(NewsResponse)
  except JsonParsingError as e:
    raise newException(Exception, "Failed to parse response: " & e.msg)

## pull executes a sources request and returns the deserialized
## SourcesResponse. The procedure accepts a SourcesRequest object containing
## optional filtering parameters for category, language, and country. The
## implementation constructs query parameters, performs the HTTP request to
## the /sources endpoint, and deserializes the JSON response. Network
## failures, API errors, and JSON parsing errors raise exceptions with
## diagnostic messages. This async procedure must be called within an async
## context using await or executed through waitFor in synchronous code.
proc pull*(req: SourcesRequest): Future[SourcesResponse] {.async.} =
  let params = toQueryParams(req)
  let endpoint = "/sources"
  var content: string
  try:
    content = await request(endpoint, params)
  except Exception as e:
    raise newException(Exception, "Failed to fetch data: " & e.msg)
  try:
    return content.parseJson().to(SourcesResponse)
  except JsonParsingError as e:
    raise newException(Exception, "Failed to parse response: " & e.msg)

## pull executes a comprehensive search request and returns the deserialized
## NewsResponse. The procedure accepts an EverythingRequest object
## containing the required search query and optional filtering, sorting, and
## pagination parameters. The implementation constructs query parameters,
## performs the HTTP request to the /everything endpoint, and deserializes
## the JSON response. Network failures, API errors, and JSON parsing errors
## raise exceptions with diagnostic messages. This async procedure must be
## called within an async context using await or executed through waitFor in
## synchronous code.
proc pull*(req: EverythingRequest): Future[NewsResponse] {.async.} =
  let params = toQueryParams(req)
  let endpoint = "/everything"
  var content: string
  try:
    content = await request(endpoint, params)
  except Exception as e:
    raise newException(Exception, "Failed to fetch data: " & e.msg)
  try:
    return content.parseJson().to(NewsResponse)
  except JsonParsingError as e:
    raise newException(Exception, "Failed to parse response: " & e.msg)
