require 'sequel'
require 'uri'

def sequel_connect(host, port, user = :me)
    login = Rake.context[:users][user.to_sym]
    adapter = Rake.context[:adapter]
    db = case adapter.to_sym
        when :mysql2
            Sequel.connect(adapter: adapter, host: host, port: port, user: login[:username], password: login[:password], database: Rake.context[:database])
        when :postgres
            Sequel.postgres(host: host, port: port, user: login[:username], password: login[:password], database: Rake.context[:database], client_min_messages: false, force_standard_strings: false)
        else
            puts "Unknown Sequel adapter type: #{adapter}"
            nil
        end
    [db, login[:username]]
end

def sequel(user = :me)
    raise "You must pass a block for this function to yield to" unless block_given?
    Rake::SSH.tunnel do |local, host, port|
        db, login =  sequel_connect(host, port, user)
        yield db
        db.disconnect
    end
end
