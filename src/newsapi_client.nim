import std/[httpclient, net, uri, strutils, strformat, asyncfutures,
  asyncdispatch, typetraits, times, json]

type

  NewsCategory* = enum
    ncBusiness = "business",
    ncEntertainment = "entertainment",
    ncGeneral = "general",
    ncHealth = "health",
    ncScience = "science",
    ncSports = "sports",
    ncTechnology = "technology"

  ## Requires either a country code or a list of source identifiers.
  HeadLinesRequest* = object
    apiKey*: string
    country*: string
    category*: NewsCategory
    sources*: seq[string] = @[]
    pageSize*: int = 20
    page*: int = 1

  NewsSourceId* = object
    id*: string
    name*: string

  NewsArticle* = object
    source*: NewsSourceId
    author*: string
    title*: string
    description*: string
    url*: string
    urlToImage*: string
    publishedAt*: string
    content*: string

  NewsResponse* = object
    status*: string
    totalResults*: int
    articles*: seq[NewsArticle]

  SourcesRequest* = object
    apiKey*: string
    category*: NewsCategory
    language*: string
    country*: string

  NewsSource* = object
    id*: string
    name*: string
    description*: string
    url*: string
    category*: NewsCategory
    language*: string
    country*: string

  SourcesResponse* = object
    status*: string
    sources*: seq[NewsSource]

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

  ErrorResponse* = object
    status*: string
    code*: ErrorCode
    message*: string

  SearchInCategory* = enum
    sicTitle = "title",
    sicDescription = "description",
    sicContent = "content"

  SortByCategory* = enum
    sbRelevancy = "relevancy",
    sbPopularity = "popularity",
    sbPublishedAt = "publishedAt"

  ## The q field is mandatory. Temporal bounds use ISO 8601 date strings
  ## (YYYY-MM-DD).
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

## SSL certificate verification is disabled for compatibility.
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

## Accepts both date-only (YYYY-MM-DD) and full datetime formats with
## timezone information.
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

proc parseCategory*(s: string): NewsCategory =
  try:
    result = parseEnum[NewsCategory](s.toLowerAscii())
  except ValueError:
    raise newException(ValueError, "Invalid category: " & s &
      ". Valid options: business, entertainment, general, health, " &
      "science, sports, technology")

proc parseSortBy*(s: string): SortByCategory =
  let normalized = s.toLowerAscii().replace("-", "")
  try:
    result = parseEnum[SortByCategory](normalized)
  except ValueError:
    raise newException(ValueError, "Invalid sort option: " & s &
      ". Valid options: relevancy, popularity, publishedAt")

proc parseSearchIn*(s: string): seq[SearchInCategory] =
  result = @[]
  for part in s.split(','):
    let normalized = part.strip().toLowerAscii()
    try:
      result.add(parseEnum[SearchInCategory](normalized))
    except ValueError:
      raise newException(ValueError, "Invalid search-in value: " & part &
        ". Valid options: title, description, content")

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
