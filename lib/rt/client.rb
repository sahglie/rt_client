#!/usr/bin/ruby

require "rubygems"
require "rest_client"
#require "iconv"
#require 'mime/types' # requires both nokogiri and rcov.  Yuck.
#require 'date'
#require 'pp'
require 'rt/util'
require 'rt/version'

module RTClient; 

	##A ruby library API to Request Tracker's REST interface. Requires the
	##rubygems rest-client, mail and mime-types to be installed.  You can
	##create a file name .rtclientrc in the same directory as client.rb with a
	##default server/user/pass to connect to RT as, so that you don't have to
	##specify it/update it in lots of different scripts.
	##
	## Thanks to Brian McArdle for patch dealing with spaces in Custom Fields.
	## To reference custom fields in RT that have spaces with rt-client, use an 
	## underscore in the rt-client code, e.g. "CF.{Has_Space}"
	##
	##TODO: Streaming, chunking attachments in compose method
	#
	# See each method for sample usage.  To use this, "gem install rt-client" and 
	#
	#  require "rt/client"
	class Client

		UA = "Mozilla/5.0 ruby RT Client Interface #{RTClient::VERSION}"
		attr_reader :status, :site, :version, :cookies, :server, :user, :cookie

		# Create a new RTClient object. Load up our stored cookie and check it.
		# Log into RT again if needed and store the new cookie.  You can specify 
		# login and cookie storage directories in 3 different ways:
		#  1. Explicity during object creation
		#  2. From a .rtclientrc file in the working directory of your ruby program
		#  3. From a .rtclientrc file in the same directory as the library itself
		#
		# These are listed in order of priority; if you have explicit parameters,
		# they are always used, even if you have .rtclientrc files.  If there
		# is both an .rtclientrc in your program's working directory and 
		# in the library directory, the one from your program's working directory
		# is used.  If no parameters are specified either explicity or by use
		# of a .rtclientrc, then the defaults of "rt_user", "rt_pass" are used
		# with a default server of "http://localhost", and cookies are stored
		# in the directory where the library resides.
		#
		#  rt= RTClient.new( :server  => "https://tickets.ambulance.com/",
		#                     :user    => "rt_user",
		#                     :pass    => "rt_pass",
		#                     :cookies => "/my/cookie/dir" )
		#
		#  rt= RTClient.new # use defaults from .rtclientrc
		#
		# .rtclientrc format:
		#  server=<RT server>
		#  user=<RT user>
		#  pass=<RT password>
		#  cookies=<directory>
		def initialize(*params)
			@boundary = "----xYzZY#{rand(1000000).to_s}xYzZY"
			@version = "0.4.0"
			@status = "Not connected"
			@server = "http://localhost/"
			@user = "rt_user"
			@pass = "rt_pass"
			@cookies = Dir.pwd
			config_file = Dir.pwd + "/.rtclientrc"
			config = ""
			if File.file?(config_file)
				config = File.read(config_file)
			else
				config_file = File.dirname(__FILE__) + "/.rtclientrc"
				config = File.read(config_file) if File.file?(config_file)
			end
			@server = $~[1] if config =~ /\s*server\s*=\s*(.*)$/i
			@user = $~[1] if config =~ /^\s*user\s*=\s*(.*)$/i
			@pass = $~[1] if config =~ /^\s*pass\s*=\s*(.*)$/i
			@cookies = $~[1] if config =~ /\s*cookies\s*=\s*(.*)$/i
			@resource = "#{@server}REST/1.0/"
			if params.class == Array && params[0].class == Hash
				param = params[0]
				@user = param[:user] if param.has_key? :user
				@pass = param[:pass] if param.has_key? :pass
				if param.has_key? :server
					@server = param[:server]
					@server += "/" if @server !~ /\/$/
					@resource = "#{@server}REST/1.0/"
				end
				@cookies  = param[:cookies] if param.has_key? :cookies
			end
			@login = { :user => @user, :pass => @pass }
			cookiejar = "#{@cookies}/RT_Client.#{@user}.cookie" # cookie location
			cookiejar.untaint
			if File.file? cookiejar
				@cookie = File.read(cookiejar).chomp
				headers = { 'User-Agent'   => UA,
				'Content-Type' => "application/x-www-form-urlencoded",
				'Cookie'       => @cookie }
			else
				headers = { 'User-Agent'   => UA,
				'Content-Type' => "application/x-www-form-urlencoded" }
				@cookie = ""
			end


			site = RestClient::Resource.new(@resource, :headers => headers, :timeout => 120)
			data = site.post "" # a null post just to check that we are logged in

			if @cookie.length == 0 or data =~ /401/ # we're not logged in
				data = site.post @login, :headers => headers
				#      puts data
				@cookie = data.headers[:set_cookie].first.split("; ")[0]
				# write the new cookie
				if @cookie !~ /nil/
					f = File.new(cookiejar,"w")
					f.puts @cookie
					f.close
				end
			end
			headers = { 'User-Agent'   => UA,
			   'Content-Type' => "multipart/form-data; boundary=#{@boundary}",
			'Cookie'       => @cookie }
			@site = RestClient::Resource.new(@resource, :headers => headers)
			@status = data
			self.untaint
		end

		# gets the detail for a single ticket/user.  If its a ticket, its without
		# history or attachments (to get those use the history method) .  If no
		# type is specified, ticket is assumed.  takes a single parameter
		# containing the ticket/user id, and returns a hash of RT Fields => values
		# 
		#  hash = rt.show(822)
		#  hash = rt.show("822")
		#  hash = rt.show("ticket/822")
		#  hash = rt.show(:id => 822)
		#  hash = rt.show(:id => "822")
		#  hash = rt.show(:id => "ticket/822")
		#  hash = rt.show("user/#{login}")
		#  email = rt.show("user/somebody")["emailaddress"]
		def show(id)
			id = id[:id] if id.class == Hash
			id = id.to_s
			type = "ticket"
			sid = id
			if id =~ /(\w+)\/(.+)/
				type = $~[1]
				sid = $~[2]
			end
			reply = {}
			if type.downcase == 'user'
				resp = @site["#{type}/#{sid}"].get
			else
				resp = @site["#{type}/#{sid}/show"].get
			end
			reply = Util.response_to_h(resp)
		end

		# Get a list of tickets matching some criteria.
		# Takes a string Ticket-SQL query and an optional "order by" parameter.
		# The order by is an RT field, prefix it with + for ascending
		# or - for descending.
		# Returns a nested array of arrays containing [ticket number, subject]
		# The outer array is in the order requested.
		#
		#  hash = rt.list(:query => "Queue = 'Sales'")
		#  hash = rt.list("Queue='Sales'")
		#  hash = rt.list(:query => "Queue = 'Sales'", :order => "-Id")
		#  hash = rt.list("Queue='Sales'","-Id")
		def list(*params)
			query = params[0]
			order = ""
			if params.size > 1
				order = params[1]
			end
			if params[0].class == Hash
				params = params[0]
				query = params[:query] if params.has_key? :query
				order = params[:order] if params.has_key? :order
			end
			reply = []
			resp = @site["search/ticket/?query=#{URI.escape(query)}&orderby=#{order}&format=s"].get
			raise "Invalid query (#{query})" if resp =~ /Invalid query/
			resp = resp.split("\n") # convert to array of lines
			resp.each do |line|
				f = line.match(/^(\d+):\s*(.*)/)
				reply.push [f[1],f[2]] if f.class == MatchData
			end
			reply
		end

		# A more extensive(expensive) query then the list method.  Takes the same
		# parameters as the list method; a string Ticket-SQL query and optional
		# order, but returns a lot more information.  Instead of just the ID and
		# subject, you get back an array of hashes, where each hash represents
		# one ticket, indentical to what you get from the show method (which only
		# acts on one ticket).  Use with caution; this can take a long time to
		# execute.
		# 
		#  array = rt.query("Queue='Sales'")
		#  array = rt.query(:query => "Queue='Sales'",:order => "+Id")
		#  array = rt.query("Queue='Sales'","+Id")
		#  => array[0] = { "id" => "123", "requestors" => "someone@..", etc etc }
		#  => array[1] = { "id" => "126", "requestors" => "someone@else..", etc etc }
		#  => array[0]["id"] = "123"
		def query(*params)
			query = params[0]
			order = ""
			if params.size > 1
				order = params[1]
			end
			if params[0].class == Hash
				params = params[0]
				query = params[:query] if params.has_key? :query
				order = params[:order] if params.has_key? :order
			end
			replies = []
			resp = @site["search/ticket/?query=#{URI.escape(query)}&orderby=#{order}&format=l"].get
			return replies if resp =~/No matching results./
			raise "Invalid query (#{query})" if resp =~ /Invalid query/
			resp.gsub!(/RT\/\d+\.\d+\.\d+\s\d{3}\s.*\n\n/,"") # strip HTTP response
			tickets = resp.split("\n--\n") # -- occurs between each ticket
			tickets.each do |ticket|
				ticket_h = Util.response_to_h(ticket)
				ticket_h.each do |k,v|
					case k
					when 'created','due','told','lastupdated','started'
						begin
							vv = DateTime.parse(v.to_s)
							reply["#{k}"] = vv.strftime("%Y-%m-%d %H:%M:%S")
						rescue ArgumentError
							reply["#{k}"] = v.to_s
						end
					else
						reply["#{k}"] = v.to_s
					end
				end
				replies.push reply
			end
			replies
		end

		# don't give up the password when the object is inspected
		def inspect # :nodoc:
			mystr = super()
			mystr.gsub!(/(.)pass=.*?([,\}])/,"\\1pass=<hidden>\\2")
			mystr
		end

	end  

end
