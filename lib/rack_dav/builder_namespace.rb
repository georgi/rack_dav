
module Builder

  class XmlBase
    def namespace(ns)
      old_namespace = @namespace
      @namespace = ns
      yield
      @namespace = old_namespace
      self
    end
    
    alias_method :method_missing_without_namespace, :method_missing
    
    def method_missing(sym, *args, &block)
      sym = "#{@namespace}:#{sym}" if @namespace
      method_missing_without_namespace(sym, *args, &block)
    end
    
  end
  
end
