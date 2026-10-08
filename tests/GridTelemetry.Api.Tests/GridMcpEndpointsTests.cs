extern alias GridMcp;

using System.Net.Http.Json;
using Microsoft.AspNetCore.Mvc.Testing;
using GridTelemetryTools = GridMcp::GridTelemetryTools;

namespace GridTelemetry.Api.Tests;

public class GridMcpEndpointsTests : IClassFixture<WebApplicationFactory<GridTelemetryTools>>
{
    private readonly HttpClient _client;

    public GridMcpEndpointsTests(WebApplicationFactory<GridTelemetryTools> factory)
    {
        _client = factory.CreateClient();
        _client.DefaultRequestHeaders.Accept.ParseAdd("application/json");
        _client.DefaultRequestHeaders.Accept.ParseAdd("text/event-stream");
    }

    [Fact]
    public async Task RegisteredMcpPathSupportsInitializationAndToolDiscovery()
    {
        using var initialize = await _client.PostAsJsonAsync("/mcp", new
        {
            jsonrpc = "2.0",
            id = 1,
            method = "initialize",
            @params = new
            {
                protocolVersion = "2025-03-26",
                capabilities = new { },
                clientInfo = new { name = "registration-test", version = "1.0" }
            }
        });
        initialize.EnsureSuccessStatusCode();
        Assert.Contains("\"protocolVersion\":\"2025-03-26\"", await initialize.Content.ReadAsStringAsync());

        if (initialize.Headers.TryGetValues("Mcp-Session-Id", out var sessionIds))
        {
            _client.DefaultRequestHeaders.Add("Mcp-Session-Id", sessionIds);
        }
        _client.DefaultRequestHeaders.Add("MCP-Protocol-Version", "2025-03-26");
        using var initialized = await _client.PostAsJsonAsync("/mcp", new
        {
            jsonrpc = "2.0",
            method = "notifications/initialized"
        });
        initialized.EnsureSuccessStatusCode();

        using var tools = await _client.PostAsJsonAsync("/mcp", new
        {
            jsonrpc = "2.0",
            id = 2,
            method = "tools/list"
        });
        tools.EnsureSuccessStatusCode();
        var content = await tools.Content.ReadAsStringAsync();
        Assert.Contains("\"name\":\"list_substations\"", content);
        Assert.Contains("\"name\":\"get_substation_health\"", content);
        Assert.DoesNotContain("\"error\":", content);
    }
}
