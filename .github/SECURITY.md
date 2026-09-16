# Security Policy

## Reporting Security Vulnerabilities

If you discover a security vulnerability, **do not** report it through GitHub issues or pull requests.

Instead, please send a detailed description directly to the Security Champion for the repository or the Security Team at [sikkerhet@klp.no](mailto:sikkerhet@klp.no).

Your report should clearly describe:

  - A description of the vulnerability.
  - Steps to reproduce the issue.
  - Any patches or workarounds (if available).
  - Potential impact and severity level.

We appreciate responsible disclosure and ensure no negative consequences for reporting vulnerabilities.

## Secure Development Guidelines

When developing code, always maintain security best practices:

  - Follow established secure coding frameworks
  - Never commit sensitive configurations (tokens, passwords) directly into the repository. Instead, use secure services like Azure Key Vault.
  - Conduct regular code reviews before merging pull requests.
  - Maintain traceability of all code contributions linked to developer identity.
  - Ensure comprehensive testing coverage, including security tests such as Static Application Security Testing (SAST) and Software Composition Analysis (SCA).

### Security Best Practices

Based on the Secure Development Guidelines, here are some points that should always be considered.

- **Input validation:** Ensure all user inputs are properly validated and sanitized.
- **Use encryption:** Always use strong encryption algorithms for storing sensitive data.
- **Use secure dependencies:** Make sure to keep dependencies up-to-date and use only well-maintained libraries.
- **Code reviews:** All code contributions should undergo a thorough code review, including a security review, before being merged.

## Required Security Scans and Tools

The following automated security scans must be conducted:

- **Static Application Security Testing (SAST)** and **Software Composition Analysis (SCA)** before merging pull requests.
  - Recommended tool: **MEND**
- **Secrets Scanning** (for passwords, tokens, etc.)
  - Tool: Currently under evaluation; contact the Security Team for recommendations.
- **Software Bill of Materials (SBOM)** must be generated upon deployment and sent to a centralized repository (solution pending).

## Secure Configuration and Deployment

- Clearly define and document security-sensitive configurations (e.g., HTTPS, authentication, and authorization).
- CI/CD pipelines must handle sensitive data securely, ideally through environment-based secrets.
- When sharing sensitive data between pipeline steps, use encrypted artifacts with keys stored securely in pipeline secrets.
- All code, including infrastructure code, must be reviewed prior to deployment to production.

## Additional Resources

- [OWASP Security Principles](https://owasp.org/www-project-top-ten/)
- [Secure Coding Practices](https://www.securecoding.cert.org/)

## Support and Contact

For questions regarding this policy or assistance with security matters, please contact the Security Team at [sikkerhet@klp.no](mailto:sikkerhet@klp.no).
