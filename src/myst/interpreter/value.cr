module Myst
  alias MTValue = Int64 | Float64 | Bool | String | MutableValue

  # Define a few methods on the primitive types to allow the interpreter to
  # treat them like any other value.
  struct ::Int64
    def type_name; "Integer"; end
    def truthy?; true; end

    def ivars; raise "Primitive values cannot have instance variables"; end
  end

  struct ::Float64
    def type_name; "Float"; end
    def truthy?; true; end

    def ivars; raise "Primitive values cannot have instance variables"; end
  end

  struct ::Bool
    def type_name; "Boolean"; end
    def truthy?; self; end

    def ivars; raise "Primitive values cannot have instance variables"; end
  end

  class ::String
    def type_name; "String"; end
    def truthy?; true; end

    def ivars; raise "Primitive values cannot have instance variables"; end
  end


  abstract class MutableValue
    # Instance variables are properties tied to the instance of an object.
    # For consistency between native (Integer, String, etc.) and language-
    # level types (IO, File, etc.), all values have an `ivars` property.
    property ivars : Scope = Scope.new

    def truthy?
      true
    end

    def type_name
      raise "Interpreter bug: unknown type name for value #{self}"
    end
  end

  abstract class ContainerType < MutableValue
    property name           : String = ""
    # Ancestors are the modules that have been included inside of a Type. For
    # example, if a module includes Enumerable, then the ancestors for that
    # module will contain Enumerable. The order of ancestors is from most to
    # least recent (the last `include` will be first in this list).
    property included_modules = [] of TModule

    def ancestors : Array(ContainerType)
      @included_modules.reduce(Set(ContainerType).new) do |acc, mod|
        acc.add(mod)
        acc.concat(mod.ancestors)
      end.to_a
    end

    def insert_ancestor(anc : TModule)
      @included_modules.unshift(anc)
    end
  end

  class TModule < ContainerType
    property scope   : Scope

    def initialize(name : String? = nil, parent : Scope? = nil)
      @name = name if name
      @scope = Scope.new(parent)
    end

    def type_name
      "Module"
    end

    def_equals_and_hash scope

    def inspect(io : IO)
      io << "%#{@name}("
      @scope.inspect(io)
      io << ")"
    end
  end

  class TType < ContainerType
    property  scope          : Scope
    property  instance_scope : Scope
    property! supertype      : TType?
    property  extended_modules = [] of TModule

    def initialize(@name : String, @supertype : TType?, parent : Scope?=nil)
      @scope = Scope.new(parent)
      @instance_scope = Scope.new(parent)
    end

    def type_name
      "Type"
    end

    def extend_module(mod : TModule)
      @extended_modules.unshift(mod)
    end

    def ancestors : Array(ContainerType)
      modules = @included_modules.reduce(Set(ContainerType).new) do |acc, mod|
        acc.add(mod)
        acc.concat(mod.ancestors)
      end

      if supertype?
        modules.add(supertype)
        modules.concat(supertype.ancestors)
      end

      modules.to_a
    end

    def extended_ancestors : Array(ContainerType)
      modules = @extended_modules.reduce(Set(ContainerType).new) do |acc, mod|
        acc.add(mod)
        acc.concat(mod.ancestors)
      end

      if supertype?
        modules.add(supertype)
        modules.concat(supertype.extended_ancestors)
      end

      modules.to_a
    end

    def_equals_and_hash name, scope, instance_scope

    def inspect(io : IO)
      io << "##{@name}(static="
      @scope.inspect(io)
      io << ", instance="
      @instance_scope.inspect(io)
      io << ")"
    end
  end

  class TInstance < MutableValue
    property type       : TType
    property scope      : Scope

    def initialize(@type : TType)
      @scope = Scope.new(@type.instance_scope)
    end

    def ancestors : Array(ContainerType)
      @type.ancestors
    end

    def type_name
      @type.name
    end

    def_equals_and_hash type, scope

    def to_s(io : IO)
      io << "<##{type_name} "
      @ivars.inspect(io)
      io << ">"
    end
  end

  class TNil < MutableValue
    # All instances of Nil in a program refer to the same object.
    NIL_OBJECT = TNil.allocate

    def self.new
      return NIL_OBJECT
    end

    def to_s
      "nil"
    end

    def truthy?
      false
    end

    def type_name
      "Nil"
    end

    def_equals_and_hash
  end

  class TSymbol < MutableValue
    SYMBOLS = {} of String => TSymbol
    @@next_id = 0_u64

    def self.new(name)
      # TODO: Revert to the following once Crystal 0.24.0 is released. This
      # currently causes a bug (see crystal-lang/crystal#4600).
      # SYMBOLS[name] ||= begin
      # instance = TSymbol.allocate
      # instance.initialize(@@next_id += 1, name)
      # SYMBOLS[name] = instance
      if SYMBOLS[name]?
        SYMBOLS[name]
      else
        instance = TSymbol.allocate
        instance.initialize(@@next_id += 1, name)
        SYMBOLS[name] = instance
      end
    end


    property value : UInt64
    property name : String

    def initialize(@value : UInt64, @name : String)
    end

    def to_s
      value.to_s
    end

    def type_name
      "Symbol"
    end

    def_equals_and_hash value
  end


  class TList < MutableValue
    property elements : Array(MTValue)

    def initialize(@elements=[] of MTValue)
    end

    def ensure_capacity(size : Int)
      count_to_add = size - self.elements.size
      count_to_add.times { self.elements.push(TNil.new) }
    end

    def type_name
      "List"
    end

    def_equals_and_hash elements
  end

  class TMap < MutableValue
    property entries : Hash(MTValue, MTValue)

    def initialize(@entries={} of MTValue => MTValue)
    end

    def type_name
      "Map"
    end

    def_equals_and_hash entries
  end


  class TFunctorDef < MutableValue
    property  definition : Def

    delegate params, block_param, block_param?, body, splat_index?, splat_index, to: definition

    def initialize(@definition : Def)
    end

    def_equals_and_hash definition
  end

  alias TNativeDef = MTValue, Array(MTValue), TFunctor? -> MTValue
  alias Callable = TFunctorDef | TNativeDef


  # A Functor is a container for multiple functor definitions, which can either
  # be language-level or native.
  class TFunctor < MutableValue
    property  name            : String
    property  clauses         : Array(Callable)
    property  lexical_scope   : Scope
    property? closure         : Bool
    property! closed_self     : MTValue?

    def initialize(@name : String, @clauses=[] of Callable, @lexical_scope : Scope=Scope.new, @closure : Bool=false, @closed_self : MTValue?=nil)
    end

    def add_clause(definition : Callable)
      clauses.push(definition)
    end

    def type_name
      "Functor"
    end

    def new_scope
      closure? ? ClosureScope.new(@lexical_scope) : Scope.new(@lexical_scope)
    end

    def_equals_and_hash name, clauses, lexical_scope

    def inspect(io : IO)
      if closure?
        io << "&&#{name}/#{clauses.size}"
      else
        io << "&#{name}/#{clauses.size}"
      end
    end
  end
end
