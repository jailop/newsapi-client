import unittest
import ../src/newsapi_client

suite "toQueryParams tests":
    
  test "HeadLinesRequest with basic fields":
    let req = HeadLinesRequest(
      apiKey: "test-key-123",
      country: "us",
      category: ncTechnology,
      pageSize: 20,
      page: 1
    )
    let params = toQueryParams(req)
    
    check params.len == 5
    check ("apiKey", "test-key-123") in params
    check ("country", "us") in params
    check ("category", "technology") in params
    check ("pageSize", "20") in params
    check ("page", "1") in params
  
  test "HeadLinesRequest with sources seq":
    let req = HeadLinesRequest(
      apiKey: "test-key",
      country: "us",
      category: ncBusiness,
      sources: @["bbc-news", "cnn"],
      pageSize: 10,
      page: 2
    )
    let params = toQueryParams(req)
    
    check ("sources", "bbc-news,cnn") in params
    check ("pageSize", "10") in params
    check ("page", "2") in params
  
  test "SourcesRequest with all fields":
    let req = SourcesRequest(
      apiKey: "api-key-xyz",
      category: ncHealth,
      language: "en",
      country: "gb"
    )
    let params = toQueryParams(req)
    
    check params.len == 4
    check ("apiKey", "api-key-xyz") in params
    check ("category", "health") in params
    check ("language", "en") in params
    check ("country", "gb") in params
  
  test "EverythingRequest with date strings":
    let req = EverythingRequest(
      apiKey: "my-api-key",
      q: "bitcoin",
      searchIn: @[sicTitle, sicDescription],
      sources: @["techcrunch", "wired"],
      domains: @["example.com"],
      excludeDomains: @["spam.com"],
      `from`: "2024-01-01",
      `to`: "2024-01-31",
      language: "en",
      sortBy: sbPopularity,
      pageSize: 50,
      page: 3
    )
    let params = toQueryParams(req)
    
    check ("apiKey", "my-api-key") in params
    check ("q", "bitcoin") in params
    check ("searchIn", "title,description") in params
    check ("sources", "techcrunch,wired") in params
    check ("domains", "example.com") in params
    check ("excludeDomains", "spam.com") in params
    check ("from", "2024-01-01") in params
    check ("to", "2024-01-31") in params
    check ("language", "en") in params
    check ("sortBy", "popularity") in params
    check ("pageSize", "50") in params
    check ("page", "3") in params
  
  test "EverythingRequest with datetime strings":
    let req = EverythingRequest(
      apiKey: "my-api-key",
      q: "test",
      `from`: "2024-01-01T00:00:00Z",
      `to`: "2024-01-31T23:59:59Z",
      pageSize: 50,
      page: 1
    )
    let params = toQueryParams(req)
    
    check ("from", "2024-01-01T00:00:00Z") in params
    check ("to", "2024-01-31T23:59:59Z") in params
  
  test "Empty strings are not included":
    let req = SourcesRequest(
      apiKey: "test",
      category: ncGeneral,
      language: "",
      country: ""
    )
    let params = toQueryParams(req)
    
    check params.len == 2
    check ("apiKey", "test") in params
    check ("category", "general") in params
  
  test "Empty sequences are not included":
    let req = HeadLinesRequest(
      apiKey: "key",
      country: "fr",
      category: ncScience,
      sources: @[],
      pageSize: 20,
      page: 1
    )
    let params = toQueryParams(req)
    
    check ("sources", "") notin params
    check params.len == 5
  
  test "Empty date values are not included":
    let req = EverythingRequest(
      apiKey: "api-key",
      q: "test",
      searchIn: @[],
      sources: @[],
      domains: @[],
      excludeDomains: @[],
      `from`: "",
      `to`: "",
      language: "",
      sortBy: sbPublishedAt,
      pageSize: 100,
      page: 1
    )
    let params = toQueryParams(req)
    
    check ("from", "") notin params
    check ("to", "") notin params
    check ("apiKey", "api-key") in params
    check ("q", "test") in params
  
  test "Invalid date format throws exception":
    let req = EverythingRequest(
      apiKey: "api-key",
      q: "test",
      `from`: "invalid-date",
      `to`: "2024-01-31",
      pageSize: 100,
      page: 1
    )
    
    expect(ValueError):
      discard toQueryParams(req)
  
  test "Invalid datetime format throws exception":
    let req = EverythingRequest(
      apiKey: "api-key",
      q: "test",
      `from`: "2024-01-01T25:00:00Z",
      `to`: "2024-01-31",
      pageSize: 100,
      page: 1
    )
    
    expect(ValueError):
      discard toQueryParams(req)

suite "parseCategory tests":
  
  test "Valid category strings":
    check parseCategory("business") == ncBusiness
    check parseCategory("BUSINESS") == ncBusiness
    check parseCategory("Business") == ncBusiness
    check parseCategory("entertainment") == ncEntertainment
    check parseCategory("general") == ncGeneral
    check parseCategory("health") == ncHealth
    check parseCategory("science") == ncScience
    check parseCategory("sports") == ncSports
    check parseCategory("technology") == ncTechnology
  
  test "Invalid category throws exception":
    expect(ValueError):
      discard parseCategory("invalid")
    
    expect(ValueError):
      discard parseCategory("tech")
    
    expect(ValueError):
      discard parseCategory("")

suite "parseSortBy tests":
  
  test "Valid sort options":
    check parseSortBy("relevancy") == sbRelevancy
    check parseSortBy("RELEVANCY") == sbRelevancy
    check parseSortBy("Relevancy") == sbRelevancy
    check parseSortBy("popularity") == sbPopularity
    check parseSortBy("publishedAt") == sbPublishedAt
    check parseSortBy("publishedat") == sbPublishedAt
    check parseSortBy("published-at") == sbPublishedAt
    check parseSortBy("PUBLISHED-AT") == sbPublishedAt
  
  test "Invalid sort option throws exception":
    expect(ValueError):
      discard parseSortBy("invalid")
    
    expect(ValueError):
      discard parseSortBy("date")
    
    expect(ValueError):
      discard parseSortBy("")

suite "parseSearchIn tests":
  
  test "Valid single search-in value":
    let result1 = parseSearchIn("title")
    check result1.len == 1
    check result1[0] == sicTitle
    
    let result2 = parseSearchIn("description")
    check result2.len == 1
    check result2[0] == sicDescription
    
    let result3 = parseSearchIn("content")
    check result3.len == 1
    check result3[0] == sicContent
  
  test "Valid multiple search-in values":
    let result1 = parseSearchIn("title,description")
    check result1.len == 2
    check sicTitle in result1
    check sicDescription in result1
    
    let result2 = parseSearchIn("title,description,content")
    check result2.len == 3
    check sicTitle in result2
    check sicDescription in result2
    check sicContent in result2
  
  test "Case insensitive search-in":
    let result = parseSearchIn("TITLE,Description,CONTENT")
    check result.len == 3
    check sicTitle in result
    check sicDescription in result
    check sicContent in result
  
  test "Whitespace handling in search-in":
    let result = parseSearchIn(" title , description , content ")
    check result.len == 3
    check sicTitle in result
    check sicDescription in result
    check sicContent in result
  
  test "Invalid search-in value throws exception":
    expect(ValueError):
      discard parseSearchIn("invalid")
    
    expect(ValueError):
      discard parseSearchIn("title,invalid,description")
    
    expect(ValueError):
      discard parseSearchIn("")

suite "validateAndFormatDate tests":
  
  test "Valid date format YYYY-MM-DD":
    check validateAndFormatDate("2024-01-01") == "2024-01-01"
    check validateAndFormatDate("2024-12-31") == "2024-12-31"
    check validateAndFormatDate("2023-06-15") == "2023-06-15"
  
  test "Valid datetime format ISO 8601":
    check validateAndFormatDate("2024-01-01T00:00:00Z") == "2024-01-01T00:00:00Z"
    check validateAndFormatDate("2024-12-31T23:59:59Z") == "2024-12-31T23:59:59Z"
  
  test "Empty string returns empty":
    check validateAndFormatDate("") == ""
  
  test "Invalid date format throws exception":
    expect(ValueError):
      discard validateAndFormatDate("2024/01/01")
    
    expect(ValueError):
      discard validateAndFormatDate("01-01-2024")
    
    expect(ValueError):
      discard validateAndFormatDate("2024-1-1")
    
    expect(ValueError):
      discard validateAndFormatDate("invalid-date")
  
  test "Invalid datetime format throws exception":
    expect(ValueError):
      discard validateAndFormatDate("2024-01-01T25:00:00Z")
    
    expect(ValueError):
      discard validateAndFormatDate("2024-13-01T00:00:00Z")
    
    expect(ValueError):
      discard validateAndFormatDate("2024-01-32T00:00:00Z")
