class Sessionize < Module
  class ProxyError < StandardError; end;
  def initialize(receiver:)
    super() do
      # define_method keeps receiver in the lexical scope
      define_method :receiver do
        session = Session.current or fail ProxyError, "#{self.name} cannot be used in a Session-less context"
        session.instance_variable_get("@%s" % receiver.to_s) or fail ProxyError, "receiver(%s) cannot be nil" % receiver
      end

      def methods(...)
        receiver.methods(...)
      end

      def respond_to?(method)
        self.receiver.respond_to?(method) or super(method)
      end

      def method_missing(method, *args, &block)
        return super unless self.respond_to?(method)
        self.receiver.send(method, *args, &block)
      end
    end
  end
end
