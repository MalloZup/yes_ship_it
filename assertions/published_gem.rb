module YSI
  class PublishedGem < Assertion
    needs "built_gem"

    def display_name
      "published gem"
    end

    def gem_file
      "#{@engine.project_name}-#{@engine.version}.gem"
    end

    def check
      begin
        json = RestClient.get("https://rubygems.org/api/v1/versions/#{engine.project_name}.json")
      rescue RestClient::ResourceNotFound
        return nil
      end
      versions = JSON.parse(json)
      versions.each do |version|
        if version["number"] == @engine.version
          return @engine.version
        end
      end
      nil
    end

    def assert(dry_run: false)
      if !dry_run
        `gem push #{gem_file}`
      end
      gem_file
    end
  end
end
