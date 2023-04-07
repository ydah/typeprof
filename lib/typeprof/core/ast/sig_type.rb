module TypeProf::Core
  class AST
    class SIG_FUNC_TYPE < Node
      def initialize(raw_decl, raw_block, lenv)
        super(raw_decl, lenv)
        if raw_block
          @block = AST.create_rbs_func_type(raw_block.type, nil, lenv)
        else
          @block = nil
        end
        # TODO: raw_decl.type_params
        @required_positionals = raw_decl.required_positionals.map do |ty|
          raise "unsupported argument type: #{ ty.class }" if !ty.is_a?(RBS::Types::Function::Param)
          AST.create_rbs_type(ty.type, lenv)
        end
        #@optional_positionals = func.optional_positionals
        #@required_keywords = func.required_keywords
        #@optional_keywords = func.optional_keywords
        #@rest_positionals = func.rest_positionals
        #@rest_keywords = func.rest_keywords
        @return_type = AST.create_rbs_type(raw_decl.return_type, lenv)
      end

      attr_reader :block, :required_positionals, :return_type

      def subnodes = { block:, required_positionals:, return_type: }
    end

    class TypeNode < Node
      def get_vertex(genv, subst)
        vtx = Vertex.new("rbs_type", self)
        get_vertex0(genv, vtx, subst)
        vtx
      end
    end

    class SIG_TY_BASE_BOOL < TypeNode
      def get_vertex0(genv, vtx, subst)
        Source.new(genv.true_type, genv.false_type).add_edge(genv, vtx)
      end
    end

    class SIG_TY_BASE_NIL < TypeNode
      def get_vertex0(genv, vtx, subst)
        Source.new(genv.nil_type).add_edge(genv, vtx)
      end
    end

    class SIG_TY_BASE_SELF < TypeNode
      def get_vertex0(genv, vtx, subst)
        subst[:__self].add_edge(genv, vtx)
      end
    end

    class SIG_TY_BASE_VOID < TypeNode
      def get_vertex0(genv, vtx, subst)
        Source.new(genv.obj_type).add_edge(genv, vtx)
      end
    end

    class SIG_TY_BASE_ANY < TypeNode
      def get_vertex0(genv, vtx, subst)
        # TODO
      end
    end

    class SIG_TY_BASE_TOP < TypeNode
      def get_vertex0(genv, vtx, subst)
        # TODO
      end
    end

    class SIG_TY_BASE_BOTTOM < TypeNode
      def get_vertex0(genv, vtx, subst)
        Source.new(Type::Bot.new).add_edge(genv, vtx)
      end
    end

    class SIG_TY_BASE_INSTANCE < TypeNode
      def get_vertex0(genv, vtx, subst)
        raise NotImplementedError
      end
    end

    class SIG_TY_ALIAS < TypeNode
      def initialize(raw_decl, lenv)
        super
        name = raw_decl.name
        @cpath = name.namespace.path
        @toplevel = name.namespace.absolute?
        @name = name.name
        @args = raw_decl.args.map {|arg| AST.create_rbs_type(arg, lenv) }
      end

      attr_reader :cpath, :toplevel, :name, :args
      def subnodes = { args: }
      def attrs = { cpath:, toplevel:, name: }

      def define0(genv)
        @args.each {|arg| arg.define(genv) }
        const_reads = []
        const_read = BaseConstRead.new(genv, @cpath.first, @toplevel ? CRef::Toplevel : @lenv.cref)
        const_reads << const_read
        unless @cpath.empty?
          @cpath[1..].each do |cname|
            const_read = ScopedConstRead.new(genv, cname, const_read)
            const_reads << const_read
          end
        end
        const_reads
      end

      def undefine0(genv)
        mod = genv.resolve_cpath(@lenv.cref.cpath)
        mod.remove_include_decl(genv, self)
        @static_ret.each do |const_read|
          const_read.destroy(genv)
        end
        @args.each {|arg| arg.undefine(genv) }
      end

      def get_vertex0(genv, vtx, subst)
        cpath = @static_ret.last.cpath
        if cpath
          tae = genv.resolve_type_alias(cpath, @name)
          if tae.exist?
            tae.decls.to_a.first.rbs_type.get_vertex0(genv, vtx, subst)
            return
          end
        end
        # TODO: report?
      end
    end

    class SIG_TY_UNION < TypeNode
      def initialize(raw_decl, lenv)
        super
        @types = raw_decl.types.map {|type| AST.create_rbs_type(type, lenv) }
      end

      attr_reader :types

      def subnodes = { types: }

      def get_vertex0(genv, vtx, subst)
        @types.each do |type|
          type.get_vertex0(genv, vtx, subst)
        end
      end
    end

    class SIG_TY_INTERSECTION < TypeNode
      def get_vertex0(genv, vtx, subst)
        #raise NotImplementedError
      end
    end

    class SIG_TY_MODULE < TypeNode
      def initialize(raw_decl, lenv)
        super
        name = raw_decl.name
        @cpath = name.namespace.path + [name.name]
        @toplevel = name.namespace.absolute?
      end

      attr_reader :cpath, :toplevel
      def attrs = { cpath:, toplevel: }

      def define0(genv)
        const_reads = []
        const_read = BaseConstRead.new(genv, @cpath.first, @toplevel ? CRef::Toplevel : @lenv.cref)
        const_reads << const_read
        unless @cpath.empty?
          @cpath[1..].each do |cname|
            const_read = ScopedConstRead.new(genv, cname, const_read)
            const_reads << const_read
          end
        end
        const_reads
      end

      def undefine0(genv)
        mod = genv.resolve_cpath(@lenv.cref.cpath)
        mod.remove_include_decl(genv, self)
        @static_ret.each do |const_read|
          const_read.destroy(genv)
        end
      end

      def get_vertex0(genv, vtx, subst)
        # TODO: type.args
        cpath = @static_ret.last.cpath
        mod = genv.resolve_cpath(cpath)
        Source.new(Type::Module.new(mod, [])).add_edge(genv, vtx)
      end
    end

    class SIG_TY_INSTANCE < TypeNode
      def initialize(raw_decl, lenv)
        super
        name = raw_decl.name
        @cpath = name.namespace.path + [name.name]
        @toplevel = name.namespace.absolute?
        @args = raw_decl.args.map {|arg| AST.create_rbs_type(arg, lenv) }
      end

      attr_reader :cpath, :toplevel, :args
      def subnodes = { args: }
      def attrs = { cpath:, toplevel: }

      def define0(genv)
        @args.each {|arg| arg.define(genv) }
        const_reads = []
        const_read = BaseConstRead.new(genv, @cpath.first, @toplevel ? CRef::Toplevel : @lenv.cref)
        const_reads << const_read
        unless @cpath.empty?
          @cpath[1..].each do |cname|
            const_read = ScopedConstRead.new(genv, cname, const_read)
            const_reads << const_read
          end
        end
        const_reads
      end

      def undefine0(genv)
        mod = genv.resolve_cpath(@lenv.cref.cpath)
        mod.remove_include_decl(genv, self)
        @static_ret.each do |const_read|
          const_read.destroy(genv)
        end
        @args.each {|arg| arg.undefine(genv) }
      end

      def get_vertex0(genv, vtx, subst)
        cpath = @static_ret.last.cpath
        case cpath
        when [:Array]
          raise if @args.size != 1
          elem_vtx = @args.first.get_vertex(genv, subst)
          Source.new(Type::Array.new(nil, elem_vtx, genv.ary_type)).add_edge(genv, vtx)
        when [:Set]
          elem_vtx = @args.first.get_vertex(genv, subst)
          Source.new(Type::Array.new(nil, elem_vtx, genv.set_type)).add_edge(genv, vtx)
        when [:Hash]
          raise if @args.size != 2
          key_vtx = @args[0].get_vertex(genv, subst)
          val_vtx = @args[1].get_vertex(genv, subst)
          Source.new(Type::Hash.new({}, key_vtx, val_vtx, genv.hash_type)).add_edge(genv, vtx)
        else
          # TODO: type.args
          mod = genv.resolve_cpath(cpath)
          Source.new(Type::Instance.new(mod, [])).add_edge(genv, vtx)
        end
      end
    end

    class SIG_TY_TUPLE < TypeNode
      def initialize(raw_decl, lenv)
        super
        @types = raw_decl.types.map {|type| AST.create_rbs_type(type, lenv) }
      end

      attr_reader :types
      def subnodes = { types: }

      def get_vertex0(genv, vtx, subst)
        unified_elem = Vertex.new("ary-unified", self)
        elems = @types.map do |type|
          nvtx = type.get_vertex(genv, subst)
          nvtx.add_edge(genv, unified_elem)
          nvtx
        end
        Source.new(Type::Array.new(elems, unified_elem, genv.ary_type)).add_edge(genv, vtx)
      end
    end

    class SIG_TY_VAR < TypeNode
      def initialize(raw_decl, lenv)
        super
        @var = raw_decl.name
      end

      attr_reader :type
      def attrs = { var: }

      def get_vertex0(genv, vtx, subst)
        if subst[@var]
          subst[@var].add_edge(genv, vtx)
        else
          #???
        end
      end
    end

    class SIG_TY_OPTIONAL < TypeNode
      def initialize(raw_decl, lenv)
        super
        @type = AST.create_rbs_type(raw_decl.type, lenv)
      end

      attr_reader :type
      def subnodes = { type: }

      def get_vertex0(genv, vtx, subst)
        @type.get_vertex0(genv, vtx, subst)
        Source.new(genv.nil_type).add_edge(genv, vtx)
      end
    end

    class SIG_TY_LITERAL < TypeNode
      def initialize(raw_decl, lenv)
        super
        @lit = raw_decl.literal
      end

      attr_reader :lit
      def attrs = { lit: }

      def get_vertex0(genv, vtx, subst)
        ty = case @lit
        when ::Symbol
          Type::Symbol.new(@lit)
        when ::Integer then genv.int_type
        when ::String then genv.str_type
        when ::TrueClass then genv.true_type
        when ::FalseClass then genv.false_type
        else
          raise "unknown RBS literal: #{ @lit.inspect }"
        end
        Source.new(ty).add_edge(genv, vtx)
      end
    end

    class SIG_TY_PROC < TypeNode
      def get_vertex0(genv, vtx, subst)
        raise NotImplementedError
      end
    end

    class SIG_TY_INTERFACE < TypeNode
      def get_vertex0(genv, vtx, subst)
        #raise NotImplementedError
      end
    end
  end
end