using System.Net;
using System.Net.Http.Json;
using Microsoft.AspNetCore.Mvc.Testing;

namespace GridTelemetry.Api.Tests;

public class GridTelemetryEndpointsTests : IClassFixture<WebApplicationFactory<Program>>
{
    private readonly HttpClient _client;

    public GridTelemetryEndpointsTests(WebApplicationFactory<Program> factory)
    {
        _client = factory.CreateClient();
    }

    [Fact]
    public async Task GetSubstationsReturnsNonEmptyList()
    {
        var substations = await _client.GetFromJsonAsync<List<SubstationDto>>("/substations");

        Assert.NotNull(substations);
        Assert.NotEmpty(substations);
        Assert.Contains(substations, substation => substation.Id == "A12" && substation.Name == "Substation A12");
    }

    [Fact]
    public async Task GetSubstationHealthForKnownIdReturnsExpectedShape()
    {
        var response = await _client.GetAsync("/substations/A12/health");

        response.EnsureSuccessStatusCode();

        var health = await response.Content.ReadFromJsonAsync<SubstationHealthDto>();

        Assert.NotNull(health);
        Assert.Equal("A12", health.Id);
        Assert.Equal("Substation A12", health.Name);
        Assert.Equal("North Valley", health.Region);
        Assert.InRange(health.HealthScore, 0, 100);
        Assert.Matches(@"^\d{4}-\d{2}-\d{2}$", health.LastInspected);
        Assert.NotNull(health.OpenMaintenanceFlags);
    }

    [Fact]
    public async Task GetSubstationHealthForUnknownIdReturnsNotFound()
    {
        var response = await _client.GetAsync("/substations/unknown/health");

        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }

    private sealed record SubstationDto(string Id, string Name, string Region);

    private sealed record SubstationHealthDto(
        string Id,
        string Name,
        string Region,
        int HealthScore,
        string LastInspected,
        string[] OpenMaintenanceFlags);
}
