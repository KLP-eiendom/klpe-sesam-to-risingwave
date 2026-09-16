using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using SharedAuth.Auth;

namespace RisingWaveDataApi.Authorization;

public class LekoOrAdminHandler : AuthorizationHandler<LekoOrAdminRequirement>
{
    public const string PolicyName = "LekoOrAdmin";

    private readonly IHttpContextAccessor accessor;
    private readonly AuthSettings settings;
    private readonly ILogger<LekoOrAdminHandler> logger;

    public LekoOrAdminHandler(IHttpContextAccessor accessor, AuthSettings settings, ILogger<LekoOrAdminHandler> logger)
    {
        this.accessor = accessor;
        this.settings = settings;
        this.logger = logger;
    }

    protected override Task HandleRequirementAsync(AuthorizationHandlerContext context, LekoOrAdminRequirement requirement)
    {
        var authHeader = this.accessor.HttpContext?.Request.Headers["Authorization"].ToString();
        if (string.IsNullOrWhiteSpace(authHeader))
        {
            context.Fail();
            return Task.CompletedTask;
        }

        try
        {
            var roleClaims = context.User.Claims.Where(c =>
                (c.Type == ClaimTypeConstants.Role || c.Type == ClaimTypeConstants.AspNetRole)
                && c.Issuer == this.settings.Authority);

            if (roleClaims.Any(c => c.Value.Contains(ClaimTypeConstants.AdminRole) || c.Value.Contains(ClaimTypeConstants.LEKORole)))
            {
                context.Succeed(requirement);
                return Task.CompletedTask;
            }
        }
        catch (Exception ex)
        {
            this.logger.LogError(ex, "Failed to authenticate");
        }

        context.Fail();
        return Task.CompletedTask;
    }
}
