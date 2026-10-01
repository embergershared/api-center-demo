using System.ComponentModel;
using ModelContextProtocol.Server;

[McpServerToolType]
public sealed class GridTelemetryTools
{
    private const string ClientName = "GridTelemetryApi";
    private readonly IHttpClientFactory _httpClientFactory;

    public GridTelemetryTools(IHttpClientFactory httpClientFactory)
    {
        _httpClientFactory = httpClientFactory;
    }

    [McpServerTool, Description("Lists the available grid substations with their ids, names, and regions so the agent can choose a valid substation before checking health.")]
    public async Task<string> ListSubstations(CancellationToken cancellationToken = default)
    {
        var client = _httpClientFactory.CreateClient(ClientName);
        using var response = await client.GetAsync("/substations", cancellationToken);

        return await CreateResultAsync(
            response,
            "Unable to retrieve substations from the Grid Telemetry API.",
            cancellationToken);
    }

    [McpServerTool, Description("Gets the current health status of a grid substation, including health score, last inspection date, and any open maintenance flags.")]
    public async Task<string> GetSubstationHealth(
        [Description("The substation id, e.g. 'A12'.")] string substationId,
        CancellationToken cancellationToken = default)
    {
        var client = _httpClientFactory.CreateClient(ClientName);
        using var response = await client.GetAsync(
            $"/substations/{Uri.EscapeDataString(substationId)}/health",
            cancellationToken);

        if (response.StatusCode == System.Net.HttpStatusCode.NotFound)
        {
            return $"No health data found for substation '{substationId}'.";
        }

        return await CreateResultAsync(
            response,
            $"Unable to retrieve health data for substation '{substationId}'.",
            cancellationToken);
    }

    private static async Task<string> CreateResultAsync(
        HttpResponseMessage response,
        string failureMessage,
        CancellationToken cancellationToken)
    {
        if (response.IsSuccessStatusCode)
        {
            return await response.Content.ReadAsStringAsync(cancellationToken);
        }

        var details = await response.Content.ReadAsStringAsync(cancellationToken);
        return string.IsNullOrWhiteSpace(details)
            ? $"{failureMessage} HTTP {(int)response.StatusCode}."
            : $"{failureMessage} HTTP {(int)response.StatusCode}: {details}";
    }
}
