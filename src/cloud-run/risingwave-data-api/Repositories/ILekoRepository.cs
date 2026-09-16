namespace RisingWaveDataApi.Repositories;

public interface ILekoRepository
{
    Task<IEnumerable<dynamic>> GetLekoDataAsync(string viewName, DateTime? updatedSince, int? limit, int offset, string? customerNumber, string? customerName);

    Task<dynamic?> GetCustomerByNumberOrNameAsync(string? customerNumber, string? customerName);

    Task<IEnumerable<dynamic>> GetUsersByCustomerIdOrNumberAsync(string? customerId, string? customerNumber, string? customerName);
}
