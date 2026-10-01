var builder = WebApplication.CreateBuilder(args);

builder.Services.AddHttpClient("GridTelemetryApi", client =>
{
    var baseUrl = builder.Configuration["GridTelemetryApi:BaseUrl"];
    client.BaseAddress = new Uri(
        string.IsNullOrWhiteSpace(baseUrl) ? "http://localhost:5000" : baseUrl);
});

builder.Services.AddMcpServer()
    .WithHttpTransport()
    .WithTools<GridTelemetryTools>();

var app = builder.Build();

app.MapMcp();

app.Run();
