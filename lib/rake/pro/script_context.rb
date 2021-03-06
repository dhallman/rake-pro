require 'erb'
require 'json/minify'

module Rake

    class ScriptContext

        attr_accessor :host
        attr_accessor :port
        attr_accessor :login
        attr_accessor :filepath
    
        def initialize(login, flags)
            @login = login
            # Set flags
            flags.each do |flag|
                instance_variable_set("@#{flag}", true)
            end
        end

        def job
            Rake.context
        end
        
        def expand template
            template.gsub!(/#\{.+?\}/) { |match|
                cv = match.split(/#\{|\}/)
                "<%= #{cv[1]} %>"
            }
            render = ERB.new(template)
            render.result(binding)
        end
        
        def inject(filename)
            template = IO.read(File.join(Rake.application.active_dir, filename))
            renderer = ERB.new(template)
            JSON.minify(renderer.result(binding))
        rescue => ex
            raise "When ERB expanding and injecting file '#{filename}':\n ]=> " + ex.message
        end

    end

    def self.run_erb_script(cmdline, user = :me, sqlfile = nil, &block)
        flags = []
        if block_given?
            script = yield
        elsif sqlfile
            parts = sqlfile.split('@')
            if parts.length == 2
            flags = parts[0].split(',')
            filename = parts[1]
            else
            filename = sqlfile
            end
            script = IO.read(File.join(Rake.application.active_dir, filename))
        else
            raise "You must either pass a sql file or sql string."
        end

        login = Rake.context[:users][user.to_sym]
        ctx = ScriptContext.new(login, flags)
        expScript = ctx.expand(script)
        scriptFile = File.join('/tmp/', 'tmp-psql-script.sql')
        File.open(scriptFile,  'w') { |file| file.write(expScript) }
        ctx.filepath = scriptFile
        ctx.login = login
        Rake::SSH.tunnel do |local, host, port|
            ctx.host = host
            ctx.port = port

            cmdLine = Rake.context['command-lines'][cmdline]
            exCmdLine = ctx.expand(cmdLine)

            if Rake.application.disconnected
                puts "\n\nIf CONNECTED, WOULD RUN:"

                puts "  $ #{exCmdLine}"
                puts "    ------------------------------------------------------------- "
                contents = IO.read(scriptFile)

                puts contents
=begin
                contents.each_line {|line| 
                    if (line.length() > 90)
                        puts "    | %s..." % line[0..90]
                    else
                        puts "    | " + line
                    end
                }
=end
                puts "    -------- END of FILE ------------------------------------------ "

            else
                local.sh exCmdLine
            end
        end
    rescue => ex
        errmsg = ""
        if !sqlfile.nil?
            errmsg = "Failed to expand or execute SQL file '#{File.join(Rake.application.active_dir, filename)}'"
        elsif block_given?
            errmsg = "Failed to export or execute SQL block passed as argument"
        end
        raise RakeTaskError.new(errmsg, ex)
    end

end

def method_missing(m, *args, &block)  
    if Rake.application.executing_task && Rake.context.has_key?('command-lines') && Rake.context['command-lines'].has_key?(m)
        Rake.application.executing_task = false
        Rake.run_erb_script(m, *args, &block)
        Rake.application.executing_task = true
    end
end  
