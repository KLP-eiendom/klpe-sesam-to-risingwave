using System.Collections.Generic;
using System.Threading.Tasks;
using RisingWaveDataApi.Models;

namespace RisingWaveDataApi.Repositories
{
    public interface IIntegrationOverviewRepository
    {
        Task<List<SystemIntegration>> GetIntegrationOverviewAsync();
    }
}
