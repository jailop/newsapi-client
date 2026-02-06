# NEWSAPI-CLIENT

## NAME

newsapi-client - Nim library and command line client for NewsAPI.org

## SYNOPSIS

### Command Line Usage

**newsapi** *command* [*options*]

**newsapi** **--help** | **--version**

### Library Usage

```nim
import newsapi_client
import asyncdispatch

let request = HeadLinesRequest(
  apiKey: "your-api-key",
  country: "us",
  category: ncTechnology,
  pageSize: 10,
  page: 1
)

let response = waitFor pull(request)
for article in response.articles:
  echo article.title
```

## DESCRIPTION

The **newsapi-client** package provides both a Nim library and
command-line utility for accessing the NewsAPI.org service. NewsAPI
aggregates news articles from over 80,000 sources worldwide, offering
programmatic access to current headlines, historical articles, and
source metadata.

The library implements a type-safe interface to the NewsAPI REST
endpoints, handling request construction, parameter validation, and
response deserialization. The command-line utility builds upon this
library to provide interactive access with human-readable output
formatting.

Authentication to NewsAPI requires an API key, which must be obtained by
registering at https://newsapi.org. NewsAPI offers free tier accounts
suitable for light usage and development.

This software is not affiliated with NewsAPI.org.

## LIBRARY INTERFACE

### Request Types

The library defines three request types corresponding to NewsAPI
endpoints. Each type is an object with fields representing the available
query parameters for that endpoint.

**HeadLinesRequest** retrieves breaking news and current top headlines.
This type requires either a country code or a list of source
identifiers. The country field accepts two-letter ISO 3166-1 codes,
while sources expects a sequence of source identifier strings. The
`category` field filters by topic using the NewsCategory enum. Pagination
is controlled through `pageSize` (1 to 100) and `page` (starting from 1)
fields. All requests must include an `apiKey` field containing the API
authentication token.

**SourcesRequest** discovers available news outlets. Unlike headline
requests, all fields are optional, allowing retrieval of the complete
source catalog. The `category`, `language`, and `country` fields filter the
result set to sources matching specified criteria. Language uses
two-letter ISO 639-1 codes.

**EverythingRequest** performs comprehensive searches across all
articles. The `q` field containing the search query is mandatory. The
`searchIn` field accepts a sequence of `SearchInCategory` values (`sicTitle`,
`sicDescription`, `sicContent`) to limit where matches occur. The `sources`,
`domains`, and `excludeDomains` fields constrain results by outlet or web
domain. Temporal bounds are specified through `from` and `to` fields as ISO
8601 date strings (YYYY-MM-DD). The `sortBy` field accepts a
`SortByCategory` value (`sbRelevancy`, `sbPopularity`, `sbPublishedAt`) to
control result ordering. As with other requests, pagination and
authentication fields are included.

### Response Types

Each request type has a corresponding response type containing the
deserialized API response.

**NewsResponse** contains a `status` field indicating success or
failure, a `totalResults` field with the count of available articles, and
an `articles` sequence containing the retrieved NewsArticle objects.

**SourcesResponse** includes `status` and `sources` fields, where `sources` is
a sequence of `NewsSource` objects describing each outlet.

### Article and Source Types

**NewsArticle** represents a single news article with fields for source
(a NewsSourceId object containing id and name), author, title,
description, url, urlToImage, publishedAt (ISO 8601 timestamp), and
content (truncated article text). Fields may be empty strings when data
is unavailable.

**NewsSource** describes a news outlet with fields for id, name,
description, url, category (NewsCategory enum), language, and country.
These objects are returned by the sources endpoint and referenced in
article source fields.

### Enumerations

**NewsCategory** defines available topic categories: ncBusiness,
ncEntertainment, ncGeneral, ncHealth, ncScience, ncSports, and
ncTechnology. Each enum value maps to the corresponding API string
value.

**SearchInCategory** specifies article fields for search matching:
sicTitle, sicDescription, and sicContent.

**SortByCategory** controls result ordering: sbRelevancy for best
matches, sbPopularity for most-shared articles, and sbPublishedAt for
chronological ordering.

### The Pull Method

The **pull** procedure is the primary interface for executing API
requests. It is defined as three overloaded async procedures, one for
each request type:

```nim
proc pull*(req: HeadLinesRequest): Future[NewsResponse] {.async.}
proc pull*(req: EverythingRequest): Future[NewsResponse] {.async.}
proc pull*(req: SourcesRequest): Future[SourcesResponse] {.async.}
```

The pull method accepts a request object and returns a Future containing
the corresponding response type. The implementation constructs the HTTP
request, handles network communication, and deserializes the JSON
response into typed objects. Network or API errors are raised as
exceptions.

Because pull is an async procedure, it must be called within an async
context using await or executed through waitFor in synchronous code. The
method handles SSL certificate verification (disabled by default for
compatibility) and sets appropriate HTTP headers for the NewsAPI
service.

Type safety is enforced at compile time through overload resolution.
Passing a HeadLinesRequest automatically returns a NewsResponse
without requiring type annotations. This eliminates runtime type
checking and potential type mismatches.

### Error Handling

API errors manifest as exceptions containing descriptive messages.
Common error conditions include authentication failures from invalid or
missing API keys, rate limiting when daily quotas are exceeded, and
validation errors for malformed parameters. Network failures during
request execution are also raised as exceptions.

The response status field indicates success ("ok") or error ("error").
Error responses may include code and message fields providing diagnostic
information, though these are typically surfaced through exceptions
rather than requiring manual checking.

## COMMAND LINE INTERFACE

The **newsapi** command-line utility provides interactive access to the
library functionality. The utility reads the API key from the
environment, constructs appropriate request objects based on
command-line arguments, invokes the pull method, and formats the
response for terminal display.

### Commands

The utility recognizes three primary commands corresponding to the API
endpoints. Command names may be abbreviated to any unambiguous prefix,
allowing **h**, **hea**, **head**, or the full **headlines** to invoke
the same functionality.

**headlines** retrieves current top news stories. Either **--country**
or **--sources** must be specified to constrain the geographic scope or
outlet selection. The **--category** parameter filters by topic.

**sources** discovers available news outlets. All parameters are
optional, with **--country**, **--language**, and **--category**
available for filtering.

**everything** performs comprehensive article searches. The **--query**
parameter is required and accepts search terms with standard operators.
Additional filters control date ranges, domains, search fields, and
result ordering.

### Options

Parameters correspond directly to request type fields, translated from
camelCase to kebab-case for command-line conventions. For instance, the
pageSize field becomes **--page-size**. Sequence fields accept
comma-separated values.

The **--country** parameter accepts two-letter ISO 3166-1 country codes
(us, gb, de, fr, etc.).

The **--category** parameter accepts topic names (business,
entertainment, general, health, science, sports, technology).

The **--sources** parameter accepts comma-separated source identifiers
discovered through the sources command.

For everything searches, **--search-in** accepts comma-separated field
names (title, description, content). The **--domains** and
**--exclude-domains** parameters filter by web domain. Date ranges use
**--from** and **--to** in YYYY-MM-DD format. The **--sort-by**
parameter accepts relevancy, popularity, or publishedAt.

The **--page-size** parameter controls result count (1-100, default 20
for headlines/sources, 100 for everything). The **--page** parameter
retrieves specific result pages (1-indexed).

Output formatting is controlled through **--markdown** (default),
**--json** (compact), or **--pretty** (indented JSON). The **--output**
parameter writes to a file instead of standard output.

### Environment

The **NEWSAPI_KEY** environment variable must contain a valid API key.
The utility exits with an error if this variable is unset. Setting the
key in shell initialization files provides persistent authentication:

```bash
export NEWSAPI_KEY="your-api-key-here"
```

## INSTALLATION

The package requires Nim 2.0 or later and depends on the standard
library's httpclient, asyncdispatch, json, and related modules. SSL
support must be enabled during compilation.

Install from the Nimble package repository:

```bash
nimble install newsapi-client
```

Or clone the repository and build locally:

```bash
git clone https://codeberg.org/jailop/newsapi-client
cd newsapi-client
nimble build
nimble install
```

## EXAMPLES

### Library Examples

Retrieve technology headlines from the United States:

```nim
import newsapi_client
import asyncdispatch

proc getHeadlines() {.async.} =
  let req = HeadLinesRequest(
    apiKey: "your-api-key",
    country: "us",
    category: ncTechnology,
    pageSize: 20,
    page: 1
  )
  
  let response = await pull(req)
  echo "Total results: ", response.totalResults
  
  for article in response.articles:
    echo "Title: ", article.title
    echo "Source: ", article.source.name
    echo "URL: ", article.url
    echo "---"

waitFor getHeadlines()
```

Search for articles about artificial intelligence:

```nim
import newsapi_client
import asyncdispatch

proc searchArticles() {.async.} =
  let req = EverythingRequest(
    apiKey: "your-api-key",
    q: "artificial intelligence",
    searchIn: @[sicTitle, sicDescription],
    `from`: "2026-01-01",
    `to`: "2026-01-31",
    language: "en",
    sortBy: sbPopularity,
    pageSize: 50,
    page: 1
  )
  
  let response = await pull(req)
  for article in response.articles:
    echo article.title
    echo article.publishedAt

waitFor searchArticles()
```

Discover English-language news sources:

```nim
import newsapi_client
import asyncdispatch

proc listSources() {.async.} =
  let req = SourcesRequest(
    apiKey: "your-api-key",
    language: "en",
    category: ncTechnology
  )
  
  let response = await pull(req)
  for source in response.sources:
    echo source.name, " (", source.id, ")"
    echo "  ", source.description

waitFor listSources()
```

### Command Line Examples

Retrieve top technology headlines from the United States:

```bash
newsapi headlines --country=us --category=technology
```

Using command abbreviation:

```bash
newsapi hea --country=us --category=technology
```

Get sources that publish in English:

```bash
newsapi sources --language=en
```

Search for articles about climate change from January 2026:

```bash
newsapi everything --query="climate change" \
  --from=2026-01-01 --to=2026-01-31 \
  --search-in=title,description
```

Retrieve headlines from specific sources in JSON format:

```bash
newsapi headlines --sources=bbc-news,cnn \
  --json --output=news.json
```

Search articles sorted by popularity with pagination:

```bash
newsapi everything --query=technology \
  --sort-by=popularity --page-size=50 --page=2
```

Export sources to a file:

```bash
newsapi sources --language=en --pretty --output=sources.json
```

## TESTING

The package includes test coverage for both library and command-line
functionality.

Run library tests:

```bash
nimble test
```

## EXIT STATUS

The command-line utility exits 0 on success and 1 on error. Error
conditions include missing or invalid API keys, unknown commands or
options, network failures, and API errors such as rate limiting or
invalid parameters.

## DIAGNOSTICS

Error messages are written to standard error. Common errors include
authentication failures when the API key is missing or invalid,
parameter validation errors when required options are omitted or values
are malformed, and API rate limit notifications when the daily quota has
been exhausted.

## SEE ALSO

Full API documentation is available at https://newsapi.org/docs

The NewsAPI terms of service are at https://newsapi.org/terms

## AUTHORS

Written for Jaime Lopez (<https://algo.datainquiry.dev>)

## BUGS

Report bugs and issues through the project repository.

Single-letter command abbreviations may become ambiguous if additional
commands beginning with the same letter are added in future versions.
Currently **h**, **s**, and **e** unambiguously map to headlines,
sources, and everything respectively.

## COPYRIGHT

This is free software: you are free to change and redistribute it.
