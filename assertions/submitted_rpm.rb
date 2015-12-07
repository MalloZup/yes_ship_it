module YSI
  class SubmittedRpm < Assertion
    parameter :obs_project

    attr_reader :obs_user, :obs_password
    attr_reader :obs_package_files

    def display_name
      "submitted RPM"
    end

    def read_obs_credentials(file_name)
      oscrc = IniFile.load(file_name)
      @obs_user = oscrc["https://api.opensuse.org"]["user"]
      @obs_password = oscrc["https://api.opensuse.org"]["pass"]
    end

    def archive_file_name
      engine.release_archive_file_name
    end

    class RpmSpecHelpers
      def initialize(engine)
        @engine = engine
      end

      def get_binding
        binding
      end

      def version
        @engine.version
      end

      def release_archive
        @engine.release_archive_file_name
      end

      def release_directory
        "#{@engine.project_name}-#{@engine.version}"
      end
    end

    def create_spec_file(template)
      erb = ERB.new(File.read(template))
      erb.result(RpmSpecHelpers.new(engine).get_binding)
    end

    def check
      if !obs_project
        @error = "OBS project is not set"
        return nil
      end
      if !engine.release_archive
        @error = "Release archive is not set. Assert release_archive before submitted_rpm"
        return nil
      end

      read_obs_credentials(File.expand_path("~/.oscrc"))

      begin
        url = "https://#{obs_user}:#{obs_password}@api.opensuse.org/source/home:cschum:go/#{engine.project_name}"
        xml = RestClient.get(url)
      rescue RestClient::Exception => e
        if e.is_a?(RestClient::ResourceNotFound)
          return nil
        elsif e.is_a?(RestClient::Unauthorized)
          @error = "No credentials set for OBS. Use osc to do this."
          return nil
        else
          @error = e.to_s
          return nil
        end
      end

      @obs_package_files = []
      doc = REXML::Document.new(xml)
      doc.elements.each("directory/entry") do |element|
        file_name = element.attributes["name"]
        @obs_package_files.push(file_name)
      end
      if @obs_package_files.include?(archive_file_name)
        return archive_file_name
      end
      nil
    end

    def assert(dry_run: false)
      engine.out.puts "..."

      old_files = []
      @obs_package_files.each do |file|
        next if file == "#{engine.project_name}.spec"
        next if file == archive_file_name
        old_files.push(file)
      end

      engine.out.puts "  Uploading release archive '#{archive_file_name}'"
      if !dry_run
        url = "https://#{obs_user}:#{obs_password}@api.opensuse.org/source/home:cschum:go/#{engine.project_name}/#{archive_file_name}"
        file = File.new(engine.release_archive, "rb")
        begin
          RestClient.put(url, file, content_type: "application/x-gzip")
        rescue RestClient::Exception => e
          STDERR.puts e.inspect
        end
      end

      spec_file = engine.project_name + ".spec"
      engine.out.puts "  Uploading spec file '#{spec_file}'"
      if !dry_run
        url = "https://#{obs_user}:#{obs_password}@api.opensuse.org/source/home:cschum:go/#{engine.project_name}/#{spec_file}"
        content = create_spec_file("rpm/#{spec_file}.erb")
        begin
          RestClient.put(url, content, content_type: "text/plain")
        rescue RestClient::Exception => e
          STDERR.puts e.inspect
        end
      end

      old_files.each do |file|
        engine.out.puts "  Removing '#{file}'"
        if !dry_run
          url = "https://#{obs_user}:#{obs_password}@api.opensuse.org/source/home:cschum:go/#{engine.project_name}/#{file}"
          RestClient.delete(url)
        end
      end

      engine.out.print "... "

      "#{obs_project}/#{engine.project_name}"
    end
  end
end