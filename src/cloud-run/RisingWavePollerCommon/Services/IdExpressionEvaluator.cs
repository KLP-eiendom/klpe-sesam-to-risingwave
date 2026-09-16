namespace RisingWavePollerCommon.Services
{
    /// <summary>
    /// Evaluates a subset of Sesam DTL-style expressions against a row dictionary.
    /// Supported functions: coalesce, concat, lower, upper, string, date.
    /// Supported atoms: column references (bare identifiers) and string literals ("...").
    /// </summary>
    public static class IdExpressionEvaluator
    {
        private enum TokenKind
        {
            Identifier,
            StringLiteral,
            OpenParen,
            CloseParen,
            Comma,
        }

        public static string Evaluate(string expression, IReadOnlyDictionary<string, object> row)
        {
            if (string.IsNullOrWhiteSpace(expression))
            {
                return null;
            }

            var tokens = Tokenize(expression);
            var pos = 0;
            return EvalExpr(tokens, ref pos, row);
        }

        private static string EvalExpr(List<Token> tokens, ref int pos, IReadOnlyDictionary<string, object> row)
        {
            var token = tokens[pos];

            if (token.Kind == TokenKind.StringLiteral)
            {
                pos++;
                return token.Value;
            }

            if (token.Kind == TokenKind.Identifier)
            {
                if (pos + 1 < tokens.Count && tokens[pos + 1].Kind == TokenKind.OpenParen)
                {
                    return EvalFunction(token.Value, tokens, ref pos, row);
                }

                pos++;
                return ColValue(token.Value, row);
            }

            throw new InvalidOperationException($"Unexpected token '{token.Value}' at position {pos}");
        }

        private static string EvalFunction(string name, List<Token> tokens, ref int pos, IReadOnlyDictionary<string, object> row)
        {
            pos++; // function name
            pos++; // '('

            var args = new List<string>();

            while (pos < tokens.Count && tokens[pos].Kind != TokenKind.CloseParen)
            {
                if (tokens[pos].Kind == TokenKind.Comma)
                {
                    pos++;
                    continue;
                }

                args.Add(EvalExpr(tokens, ref pos, row));
            }

            if (pos < tokens.Count)
            {
                pos++; // ')'
            }

            return name.ToLowerInvariant() switch
            {
                "coalesce" => args.FirstOrDefault(a => !string.IsNullOrEmpty(a)),
                "concat" => string.Concat(args.Select(a => a ?? string.Empty)),
                "lower" => args.FirstOrDefault()?.ToLowerInvariant(),
                "upper" => args.FirstOrDefault()?.ToUpperInvariant(),
                "string" => args.FirstOrDefault(),
                "date" => ToDateString(args.FirstOrDefault()),
                _ => throw new InvalidOperationException($"Unknown function '{name}'"),
            };
        }

        private static string ColValue(string columnName, IReadOnlyDictionary<string, object> row)
        {
            if (!row.TryGetValue(columnName, out var value) || value is null || value == DBNull.Value)
            {
                return null;
            }

            return value switch
            {
                DateTime dt => dt.ToString("O"),
                DateTimeOffset dto => dto.UtcDateTime.ToString("O"),
                _ => value.ToString(),
            };
        }

        private static string ToDateString(string value)
        {
            if (value is null)
            {
                return null;
            }

            return DateTime.TryParse(value, out var dt)
                ? dt.ToString("yyyy-MM-dd")
                : value;
        }

        private static List<Token> Tokenize(string input)
        {
            var tokens = new List<Token>();
            var i = 0;

            while (i < input.Length)
            {
                if (char.IsWhiteSpace(input[i]))
                {
                    i++;
                    continue;
                }

                if (input[i] == '(')
                {
                    tokens.Add(new Token(TokenKind.OpenParen, "("));
                    i++;
                    continue;
                }

                if (input[i] == ')')
                {
                    tokens.Add(new Token(TokenKind.CloseParen, ")"));
                    i++;
                    continue;
                }

                if (input[i] == ',')
                {
                    tokens.Add(new Token(TokenKind.Comma, ","));
                    i++;
                    continue;
                }

                if (input[i] == '"')
                {
                    i++;
                    var start = i;
                    while (i < input.Length && input[i] != '"')
                    {
                        i++;
                    }

                    tokens.Add(new Token(TokenKind.StringLiteral, input[start..i]));
                    i++;
                    continue;
                }

                if (char.IsLetter(input[i]) || input[i] == '_')
                {
                    var start = i;
                    while (i < input.Length && (char.IsLetterOrDigit(input[i]) || input[i] == '_'))
                    {
                        i++;
                    }

                    tokens.Add(new Token(TokenKind.Identifier, input[start..i]));
                    continue;
                }

                throw new InvalidOperationException($"Unexpected character '{input[i]}' at position {i} in expression: {input}");
            }

            return tokens;
        }

        private readonly struct Token
        {
            public Token(TokenKind kind, string value)
            {
                this.Kind = kind;
                this.Value = value;
            }

            public TokenKind Kind { get; }

            public string Value { get; }
        }
    }
}
