# Contributing to the Sesam to RisingWave Showcase

Thank you for your interest in contributing to this reference architecture! We welcome suggestions, questions, and improvements from other Sesam customers and data engineers transitioning to streaming SQL.

---

## How to Contribute

1. **Open an Issue**: For discussion, feature ideas, questions about Sesam-to-RisingWave translation, or bug reports.
2. **Submit a Pull Request**:
   - Fork the repository.
   - Create a feature branch (`git checkout -b feature/my-improvement`).
   - Run linter: `sqlfluff lint dbt/models`
   - Run unit tests: `cd dbt && dbt test --target localdev`
   - Commit your changes with clear messages.
   - Open a PR describing what was changed and why.

---

## Code Quality Standards

- **SQL Conventions**: Follow dbt best practices (lowercase keywords, snake_case model names).
- **Streaming SQL**: Ensure Materialized Views comply with RisingWave stream processing rules (e.g. streaming temporal filters, explicit primary keys on tables).
- **Zero Secrets**: Never commit environment files (`.env.*`), tokens, internal cluster URLs, or personal data. Use synthetic/fictional test data.

---

## License

By contributing, you agree that your contributions will be licensed under the project's [MIT License](LICENSE).
