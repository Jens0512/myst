require "spec"
require "../src/myst/**"

include Myst

# Run the Myst parser on the given source code, returning the AST that the
# parser generates for it.
def parse_program(source : String) : Expressions
  parser = Parser.new(IO::Memory.new(source), __DIR__)
  parser.parse
end

# Return the list of tokens generated by lexing the given source. Parsing is
# not performed, so semantically-invalid sequences are allowed by this method.
def tokenize(source : String)
  parser = Parser.new(IO::Memory.new(source), __DIR__)
  parser.lex_all
  parser.tokens
end

# Assert that the given source causes a syntax error
def assert_syntax_error(source : String)
  expect_raises(SyntaxError) do
    tokenize(source)
  end
end

# Assert that given source is accepted by the parser. The given source will not
# be executed by this method.
# Currently, this method just invokes the parser to ensure no errors occur.
def assert_valid(source)
  parse_program(source)
end

# Inverse of `assert_valid`: Assert that the given source causes a ParseError.
def assert_invalid(source)
  expect_raises(ParseError) do
    parse_program(source)
  end
end

# Parse and run the given program, returning the interpreter that ran the
# program to be used for making assertions.
def parse_and_interpret(source, interpreter=Interpreter.new)
  program = parse_program(source)
  program.accept(interpreter)
  interpreter
end
