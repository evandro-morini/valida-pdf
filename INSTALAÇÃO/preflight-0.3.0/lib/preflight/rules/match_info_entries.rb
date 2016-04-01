# encoding: US-ASCII
module Preflight
  module Rules
    # Every PDF has an optional 'Info' dictionary. Check that the target file
    # has certain keys and that the keys match a given regexp
    #
    # Arguments: the required keys
    #
    # Usage:
    #
    #   class MyPreflight
    #     include Preflight::Profile
    #
    #     rule Preflight::Rules::MatchInfoEntries, {:GTS_PDFXVersion => /\APDF\/X/}
    #   end
    #
    class MatchInfoEntries

      def initialize(matches = {})
        @matches = matches
      end

      def check_hash(ohash)
        array = []        
        info = ohash.object(ohash.trailer[:Info])        
        
        @matches.each do |key, regexp|                  
          
          @cleanStr =  info[key].to_s.gsub(/[\x00|\xFE|\xFF]/,'')

          if !info.has_key?(key)            
            array << Issue.new("Info dict missing required key", self, :key => key)
          elsif !@cleanStr.match(regexp)
            array << Issue.new("value of Info #{@algo} entry #{key} doesn't match #{regexp}", self, :key    => key,
                                                                                           :regexp => regexp,
                                                                                           :algo   => @cleanStr)
          end
        end
        array
      end
    end
  end
end
