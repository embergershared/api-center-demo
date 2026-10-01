using System.Security.Cryptography;
using System.Text;

var builder = WebApplication.CreateBuilder(args);

// Add services to the container.
// Learn more about configuring OpenAPI at https://aka.ms/aspnet/openapi
builder.Services.AddOpenApi();

var app = builder.Build();

// Always expose the OpenAPI document, including in Production on App Service,
// so API Center can import the live specification (see scripts/10-register-grid-telemetry-api.ps1).
app.MapOpenApi();

var substations = new[]
{
    new Substation("A12", "Substation A12", "North Valley"),
    new Substation("B07", "Substation B07", "River Bend"),
    new Substation("C19", "Substation C19", "South Ridge"),
    new Substation("D04", "Substation D04", "East Junction"),
    new Substation("E23", "Substation E23", "Lake Corridor"),
    new Substation("F15", "Substation F15", "West Prairie")
};

var substationsById = substations.ToDictionary(substation => substation.Id, StringComparer.OrdinalIgnoreCase);

var substationsGroup = app.MapGroup("/substations")
    .WithTags("Grid Telemetry");

substationsGroup.MapGet(string.Empty, () => substations)
    .WithName("GetSubstations")
    .WithSummary("Lists synthetic substations.")
    .WithDescription("Returns demo-safe synthetic substations for the Grid Maintenance Agent scenario.")
    .Produces<Substation[]>(StatusCodes.Status200OK);

substationsGroup.MapGet("/{id}/health", (string id) =>
    {
        if (!substationsById.TryGetValue(id, out var substation))
        {
            return Results.NotFound();
        }

        return Results.Ok(CreateHealthSnapshot(substation));
    })
    .WithName("GetSubstationHealth")
    .WithSummary("Gets synthetic substation health details.")
    .WithDescription("Returns a stable synthetic health snapshot and open maintenance flags for a single substation.")
    .Produces<SubstationHealth>(StatusCodes.Status200OK)
    .Produces(StatusCodes.Status404NotFound);

app.Run();

static SubstationHealth CreateHealthSnapshot(Substation substation)
{
    var hash = SHA256.HashData(Encoding.UTF8.GetBytes(substation.Id));
    var healthScore = hash[0] % 101;
    var lastInspected = new DateOnly(2026, 9, 28).AddDays(-(hash[1] % 45));

    var possibleFlags = new[]
    {
        "Vegetation review scheduled",
        "Transformer oil sample pending",
        "Thermal scan recommended",
        "Breaker timing inspection due",
        "Battery backup verification"
    };

    var openMaintenanceFlags = possibleFlags
        .Where((_, index) => (hash[2 + index] & 1) == 1)
        .Take(3)
        .ToArray();

    return new SubstationHealth(
        substation.Id,
        substation.Name,
        substation.Region,
        healthScore,
        lastInspected,
        openMaintenanceFlags);
}

record Substation(string Id, string Name, string Region);

record SubstationHealth(
    string Id,
    string Name,
    string Region,
    int HealthScore,
    DateOnly LastInspected,
    string[] OpenMaintenanceFlags);

public partial class Program
{
}
