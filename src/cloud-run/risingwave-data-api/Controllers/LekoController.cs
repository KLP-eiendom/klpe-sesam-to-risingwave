using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Infrastructure;
using Npgsql;
using RisingWaveDataApi.Authorization;
using RisingWaveDataApi.Repositories;
using SharedAuth.Auth;
using SharedAuth.Controllers;

namespace RisingWaveDataApi.Controllers;

/// <summary>
/// Controller for retrieving Leko-related data from RisingWave marts.
/// </summary>
[ApiController]
[Route("api/v1/leko")]
[Authorize(Policy = LekoOrAdminHandler.PolicyName)]
public class LekoController : KundeportalControllerBase
{
    private readonly ILekoRepository lekoRepository;
    private readonly ILogger<LekoController> logger;

    public LekoController(
        ILekoRepository lekoRepository,
        ILogger<LekoController> logger,
        AuthSettings authSettings,
        IActionContextAccessor httpContextAccessor)
        : base(httpContextAccessor, authSettings)
    {
        this.lekoRepository = lekoRepository;
        this.logger = logger;
    }

    /// <summary>
    /// Retrieves building data from the mrt_bygg_leko view.
    /// </summary>
    /// <param name="customer_number">Optional filter by customer number or customer ID.</param>
    /// <param name="customer_name">Optional filter by customer name.</param>
    /// <param name="updated_since">Optional filter to retrieve records updated after the specified timestamp.</param>
    /// <param name="limit">Maximum number of records to return. If omitted (null), all records are returned.</param>
    /// <param name="offset">Number of records to skip for pagination (default: 0).</param>
    /// <returns>A list of building data records.</returns>
    [HttpGet("bygg")]
    [ProducesResponseType(StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    [ProducesResponseType(StatusCodes.Status500InternalServerError)]
    public async Task<IActionResult> GetBygg(
        [FromQuery] string? customer_number,
        [FromQuery] string? customer_name,
        [FromQuery] DateTime? updated_since,
        [FromQuery] int? limit = null,
        [FromQuery] int offset = 0)
    {
        return await FetchData("mrt_bygg_leko", updated_since, limit, offset, customer_number, customer_name);
    }

    /// <summary>
    /// Retrieves building drawing data from the mrt_byggtegning_leko view.
    /// </summary>
    /// <param name="customer_number">Optional filter by customer number or customer ID.</param>
    /// <param name="customer_name">Optional filter by customer name.</param>
    /// <param name="updated_since">Optional filter to retrieve records updated after the specified timestamp.</param>
    /// <param name="limit">Maximum number of records to return. If omitted (null), all records are returned.</param>
    /// <param name="offset">Number of records to skip for pagination (default: 0).</param>
    /// <returns>A list of building drawing records.</returns>
    [HttpGet("byggtegning")]
    [ProducesResponseType(StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    [ProducesResponseType(StatusCodes.Status500InternalServerError)]
    public async Task<IActionResult> GetByggtegning(
        [FromQuery] string? customer_number,
        [FromQuery] string? customer_name,
        [FromQuery] DateTime? updated_since,
        [FromQuery] int? limit = null,
        [FromQuery] int offset = 0)
    {
        return await FetchData("mrt_byggtegning_leko", updated_since, limit, offset, customer_number, customer_name);
    }

    /// <summary>
    /// Retrieves customer data from the mrt_customer_leko view.
    /// </summary>
    /// <param name="customer_number">Optional filter by customer number or customer ID.</param>
    /// <param name="customer_name">Optional filter by customer name.</param>
    /// <param name="updated_since">Optional filter to retrieve records updated after the specified timestamp.</param>
    /// <param name="limit">Maximum number of records to return. If omitted (null), all records are returned.</param>
    /// <param name="offset">Number of records to skip for pagination (default: 0).</param>
    /// <returns>A list of customer records.</returns>
    [HttpGet("customer")]
    [ProducesResponseType(StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    [ProducesResponseType(StatusCodes.Status500InternalServerError)]
    public async Task<IActionResult> GetCustomer(
        [FromQuery] string? customer_number,
        [FromQuery] string? customer_name,
        [FromQuery] DateTime? updated_since,
        [FromQuery] int? limit = null,
        [FromQuery] int offset = 0)
    {
        return await FetchData("mrt_customer_leko", updated_since, limit, offset, customer_number, customer_name);
    }

    /// <summary>
    /// Retrieves user data from the mrt_user_leko view.
    /// </summary>
    /// <param name="customer_number">Optional filter by customer number or customer ID.</param>
    /// <param name="customer_name">Optional filter by customer name.</param>
    /// <param name="updated_since">Optional filter to retrieve records updated after the specified timestamp.</param>
    /// <param name="limit">Maximum number of records to return. If omitted (null), all records are returned.</param>
    /// <param name="offset">Number of records to skip for pagination (default: 0).</param>
    /// <returns>A list of user records.</returns>
    [HttpGet("user")]
    [ProducesResponseType(StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    [ProducesResponseType(StatusCodes.Status500InternalServerError)]
    public async Task<IActionResult> GetUser(
        [FromQuery] string? customer_number,
        [FromQuery] string? customer_name,
        [FromQuery] DateTime? updated_since,
        [FromQuery] int? limit = null,
        [FromQuery] int offset = 0)
    {
        return await FetchData("mrt_user_leko", updated_since, limit, offset, customer_number, customer_name);
    }

    /// <summary>
    /// Retrieves aggregated customer information and associated users based on customer number or customer name.
    /// </summary>
    /// <param name="customer_number">Customer number or customer ID.</param>
    /// <param name="customer_name">Customer name.</param>
    /// <returns>An object containing customer details and linked users.</returns>
    [HttpGet("customer/aggregate")]
    [ProducesResponseType(StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    [ProducesResponseType(StatusCodes.Status500InternalServerError)]
    public async Task<IActionResult> GetCustomerAggregate(
        [FromQuery] string? customer_number,
        [FromQuery] string? customer_name)
    {
        if (string.IsNullOrWhiteSpace(customer_number) && string.IsNullOrWhiteSpace(customer_name))
        {
            return BadRequest(new { error = "Du må oppgi enten kundenummer (customer_number) eller kundenavn (customer_name)." });
        }

        try
        {
            var customer = await this.lekoRepository.GetCustomerByNumberOrNameAsync(customer_number, customer_name);

            if (customer == null)
            {
                return NotFound(new { message = "Kunde ikke funnet." });
            }

            IDictionary<string, object>? customerDict = customer as IDictionary<string, object>;
            if (customerDict == null)
            {
                this.logger.LogError("Kundeobjektet kunne ikke konverteres til en ordbok for videre behandling.");
                return StatusCode(500, new { error = "En intern feil oppstod ved behandling av kundeinformasjonen." });
            }

            // Extract IDs for linked users
            string? resolvedId = customerDict.TryGetValue("id", out object? idVal) ? idVal?.ToString() : null;
            string? resolvedNo = customerDict.TryGetValue("customer_number", out object? noVal) ? noVal?.ToString() : null;

            var users = await this.lekoRepository.GetUsersByCustomerIdOrNumberAsync(resolvedId, resolvedNo, customer_name);

            return Ok(new
            {
                Customer = customer,
                Users = users
            });
        }
        catch (PostgresException ex) when (ex.SqlState == "42P01")
        {
            this.logger.LogWarning(ex, "En eller flere tabeller/views mangler i databasen.");
            return NotFound(new { error = "Noen av datakildene mangler i databasen." });
        }
        catch (Exception ex)
        {
            this.logger.LogError(ex, "Feil ved kjøring av aggregert spørring.");
            return StatusCode(500, new { error = "En intern feil oppstod." });
        }
    }

    private async Task<IActionResult> FetchData(
        string viewName,
        DateTime? updatedSince,
        int? limit,
        int offset,
        string? customerNumber,
        string? customerName)
    {
        if (offset < 0)
        {
            offset = 0;
        }

        try
        {
            var results = await this.lekoRepository.GetLekoDataAsync(viewName, updatedSince, limit, offset, customerNumber, customerName);
            return Ok(results);
        }
        catch (PostgresException ex) when (ex.SqlState == "42P01")
        {
            this.logger.LogWarning(ex, "View {ViewName} finnes ikke i databasen.", viewName);
            return NotFound(new { error = $"Entiteten {viewName} er ikke tilgjengelig i databasen." });
        }
        catch (Exception ex)
        {
            this.logger.LogError(ex, "Feil ved henting av data for {ViewName}", viewName);
            return StatusCode(500, new { error = "En intern feil oppstod under uthenting av data." });
        }
    }
}