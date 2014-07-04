module GenericApiRails
  class RestController < BaseController
    before_filter :setup
    before_filter :model
    skip_before_filter :verify_authenticity_token

    def render_json(data)
      render_one = lambda do |m|
        include = m.class.reflect_on_all_associations.select do 
          |a| a.macro == :has_and_belongs_to_many or a.macro == :has_one
        end.map do |a|
          h = {}
          h[a.name] = { :only => [:id] }
          h
        end

        h = { :model => m.as_json(:include => include) }
        if m.errors.keys
          h[:errors] = m.errors.messages
        end

        h
      end
      
      if data.respond_to? :collect
        meta = {}
        if data.respond_to? :count
          meta[:total] = data.count
        end

        data = data.limit(@limit) if @limit
        data = data.offset(@offset) if @offset

        meta[:rows] = data.collect(&render_one)

        render :json => meta
      else
        render :json => render_one.call(data)
      end
    end

    def setup
      @rest = params[:rest]
      @action = params[:action]
      @controller = self
    end

    def model
      namespace ||= params[:namespace].camelize if params.has_key? :namespace
      model_name ||= params[:model].singularize.camelize
      if namespace
        qualified_name = "#{namespace}::#{model_name}" 
      else
        qualified_name = model_name
      end
      @model = qualified_name.constantize
    end

    def authorized?(action, resource)
      GenericApiRails.config.authorize_with.call(@authenticated, action, resource)
    end

    def id_list
      ids = params[:ids].split ','
      @instances = model.where(:id => ids)
      
      render_error(ApiError::UNAUTHORIZED) and return false unless authorized?(:read, @instances)

      render_json @instances
    end
    
    def index
      if params[:ids]
        id_list
      else
        search_hash = {}
        do_search = false
        special_handler = false

        @instances = nil

        params.each do |key,value|
          unless special_handler
            special_handler ||= GenericApiRails.config.search_for(@model, key)
            if special_handler
              puts "Calling special handler #{key} with #{value}"
              @instances = instance_exec(value, &special_handler)
            end
          end
        end

        unless special_handler
          model.columns.each do |c|
            name = c.name
            search_hash[name.to_sym] = params[name] and do_search=true if params[name]
          end
        end
        
        if do_search
          @instances = model.where(search_hash)
          render_error(ApiError:UNAUTHORIZED) and return false unless authorized?(:read, @instances)
        elsif special_handler
          render_error(ApiError:UNAUTHORIZED) and return false unless authorized?(:read, @instances)
        else
          render_error(ApiError::UNAUTHORIZED) and return false unless authorized?(:index, model)
          @instances = model.all
        end
        
        @limit = params[:limit]
        @offset = params[:offset]
#        @instances = r.limit(1000) if @instances.respond_to? :limit

        render_json @instances
      end
    end

    def read
      @instance = @model.find(params[:id])

      render_error(ApiError::UNAUTHORIZED) and return false unless authorized?(:read, @instance)

      render_json @instance
    end

    def create
      hash = params[:rest]
      @instance = model.new()
      # params.require(:rest).permit(params[:rest].keys.collect { |k| k.to_sym })

      @instance.assign_attributes(hash.to_hash)

      render_error(ApiError::UNAUTHORIZED) and return false unless authorized?(:create, @instance)
      @instance.save
      # puts "INSTANCE: ", @instance.attributes.to_s
 
      render_json @instance
    end

    def update
      hash = params[:rest]

      @instance = @model.find(params[:id])
      @instance.assign_attributes(hash.to_hash)

      render_error(ApiError::UNAUTHORIZED) and return false unless authorized?(:update, @instance)

      @instance.save

      render_json @instance
    end

    def destroy
      @instance = model.find(params[:id])

      render_error(ApiError::UNAUTHORIZED) and return false unless authorized?(:destroy, @instance)

      @instance.destroy!
      
      render :json => { success: true }
    end
  end
end
