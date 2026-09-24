using Dapper;
using Npgsql;

namespace RisingWaveDataApi.Repositories;

public class LekoRepository : ILekoRepository
{
    private static readonly HashSet<string> AllowedViews = new()
    {
        "mrt_bygg_leko",
        "mrt_byggtegning_leko",
        "mrt_customer_leko",
        "mrt_user_leko",
    };

    private readonly NpgsqlDataSource dataSource;

    public LekoRepository(NpgsqlDataSource dataSource)
    {
        this.dataSource = dataSource;
    }

    public async Task<IEnumerable<dynamic>> GetLekoDataAsync(string viewName, DateTime? updatedSince, int? limit, int offset, string? customerNumber, string? customerName)
    {
        if (!AllowedViews.Contains(viewName))
        {
            throw new ArgumentException($"View '{viewName}' is not an allowed data source.", nameof(viewName));
        }

        await using var connection = await this.dataSource.OpenConnectionAsync();

        string sql = $"SELECT * FROM {viewName} WHERE 1=1";
        var parameters = new DynamicParameters();

        if (updatedSince.HasValue)
        {
            sql += " AND _updated_at >= @UpdatedSince";
            parameters.Add("UpdatedSince", updatedSince.Value);
        }

        if (!string.IsNullOrWhiteSpace(customerNumber))
        {
            sql += " AND (customer_number = @CustNo OR customer_id = @CustNo OR id = @CustNo)";
            parameters.Add("CustNo", customerNumber);
        }

        if (!string.IsNullOrWhiteSpace(customerName))
        {
            sql += " AND (name ILIKE @CustName OR customer_name ILIKE @CustName)";
            parameters.Add("CustName", $"%{customerName}%");
        }

        if (limit.HasValue)
        {
            sql += $" LIMIT {limit.Value}";
        }

        if (offset > 0)
        {
            sql += $" OFFSET {offset}";
        }

        return await connection.QueryAsync(sql, parameters);
    }

    public async Task<dynamic?> GetCustomerByNumberOrNameAsync(string? customerNumber, string? customerName)
    {
        await using var connection = await this.dataSource.OpenConnectionAsync();

        string sql = "SELECT * FROM mrt_customer_leko WHERE 1=1";
        var parameters = new DynamicParameters();

        if (!string.IsNullOrWhiteSpace(customerNumber))
        {
            sql += " AND (customer_number = @CustNo OR id = @CustNo)";
            parameters.Add("CustNo", customerNumber);
        }

        if (!string.IsNullOrWhiteSpace(customerName))
        {
            sql += " AND (name ILIKE @CustName OR customer_name ILIKE @CustName)";
            parameters.Add("CustName", $"%{customerName}%");
        }

        var customers = await connection.QueryAsync<dynamic>(sql, parameters);
        return customers.FirstOrDefault();
    }

    public async Task<IEnumerable<dynamic>> GetUsersByCustomerIdOrNumberAsync(string? customerId, string? customerNumber, string? customerName)
    {
        await using var connection = await this.dataSource.OpenConnectionAsync();

        string sql = "SELECT * FROM mrt_user_leko WHERE 1=1";
        var parameters = new DynamicParameters();

        if (!string.IsNullOrWhiteSpace(customerId) || !string.IsNullOrWhiteSpace(customerNumber))
        {
            sql += " AND (customer_id = @Id OR customer_number = @No)";
            parameters.Add("Id", customerId);
            parameters.Add("No", customerNumber);
        }
        else if (!string.IsNullOrWhiteSpace(customerName))
        {
            sql += " AND customer_name ILIKE @CustName";
            parameters.Add("CustName", $"%{customerName}%");
        }

        return await connection.QueryAsync<dynamic>(sql, parameters);
    }
}
