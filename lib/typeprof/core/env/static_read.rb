module TypeProf::Core
  class StaticRead
    def initialize(name)
      @name = name
      @followers = Set[]
      @source_modules = []
    end

    attr_reader :name, :followers

    def propagate(genv)
      @followers.dup.each do |follower|
        case follower
        when ModuleEntity
          follower.on_parent_modules_changed(genv)
        when ScopedStaticRead
          follower.on_cbase_updated(genv)
        when ConstReadSite, IsAFilter
          genv.add_run(follower)
        else
          raise follower.inspect
        end
      end
    end

    def destroy(genv)
      @source_modules.each do |mod|
        mod.static_reads[@name].delete(self)
      end
      @source_modules.clear
    end

    def resolve(genv, cref, break_object)
      destroy(genv)

      first = true
      while cref
        scope = cref.cpath
        mod = genv.resolve_cpath(scope)
        while true
          @source_modules << mod
          (mod.static_reads[@name] ||= Set[]) << self

          return if check_module(genv, mod)

          # TODO: included modules

          break unless first
          break unless mod.superclass
          break if mod.cpath == [:BasicObject]
          mod = mod.superclass
          break if mod.cpath == [] && break_object
        end
        first = false
        cref = cref.outer
      end
      resolution_failed(genv)
    end
  end

  class BaseStaticRead < StaticRead
    def initialize(genv, name, cref)
      super(name)
      @cref = cref
      genv.add_static_eval_queue(:static_read_changed, self)
    end

    attr_reader :cref

    def on_scope_updated(genv)
      resolve(genv, @cref, false)
    end
  end

  class ScopedStaticRead < StaticRead
    def initialize(name, cbase)
      super(name)
      @cbase = cbase
      @cbase.followers << self if @cbase
    end

    def on_cbase_updated(genv)
      if @cbase && @cbase.cpath
        resolve(genv, CRef.new(@cbase.cpath, false, nil), true)
      else
        resolution_failed(genv)
      end
    end
  end

  module ConstRead
    def check_module(genv, mod)
      cdef = mod.consts[@name]
      if cdef && cdef.exist?
        inner_mod = genv.resolve_cpath(mod.cpath + [@name]) # TODO
        cpath = inner_mod.exist? ? inner_mod.cpath : nil
        update_module(genv, cpath, cdef)
        return true
      end
      return false
    end

    def resolution_failed(genv)
      update_module(genv, nil, nil)
    end

    def update_module(genv, cpath, cdef)
      if cpath != @cpath || cdef != @cdef
        @cpath = cpath
        @cdef = cdef
        propagate(genv)
      end
    end

    attr_reader :cpath, :cdef
  end

  class BaseConstRead < BaseStaticRead
    include ConstRead
  end

  class ScopedConstRead < ScopedStaticRead
    include ConstRead
  end

  module TypeAliasRead
    def check_module(genv, mod)
      tae = mod.type_aliases[@name]
      if tae && tae.exist?
        update_type_alias(genv, tae)
        return true
      end
      return false
    end

    def resolution_failed(genv)
      update_type_alias(genv, nil)
    end

    def update_type_alias(genv, tae)
      if tae != @type_alias_entity
        @type_alias_entity = tae
        propagate(genv)
      end
    end

    attr_reader :type_alias_entity
  end

  class BaseTypeAliasRead < BaseStaticRead
    include TypeAliasRead
  end

  class ScopedTypeAliasRead < ScopedStaticRead
    include TypeAliasRead
  end
end