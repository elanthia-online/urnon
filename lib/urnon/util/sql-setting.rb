require 'urnon/session'

class SqlSetting < Module
  def initialize(table:, &scope)
    super() do
      # define_method keeps receiver in the lexical scope
      define_method :query do
        scope.call
      end

      define_method :table do
        Lich.db[table]
      end

      define_method :fetch do
        self.decode self.table.first(**self.query).fetch(:hash)
      end

      define_method :save do |hash|
        blob = Sequel.blob(Marshal.dump(hash))
        self.table.insert_conflict(:update).insert(**self.query.merge({hash: blob}))
      end

      def decode(blob)
        if blob.nil?
          {}
        else
          Marshal.load blob
        end
      end

      def find(**query)
        self.decode self.table.first(**query).fetch(:hash)
      end

      def mutate()
        vars = self.fetch
        yield(vars)
        save(vars)
      end

      def [](name)
        #pp("%s[query=%s, :%s]" % [self.query, self.name, name], self.fetch)
        self.fetch[name]
      end

      def delete(name)
        vars = self.fetch
        vars.delete(name)
        save(vars)
      end

      def []=(name, val)
        return delete(name) if val.nil?
        vars = self.fetch
        vars[name] = val
      end

      def to_hash
        self.fetch
      end

      def to_h
        self.fetch
      end

      def list
        self.fetch
      end

      def method_missing(arg1, arg2='')
        return self[arg1.to_s] if arg1[-1,1] != '='
        return self.delete(arg1.to_s.chop) if arg2.nil?
        self[arg1.to_s.chop] = arg2
      end
    end
  end
end
