module RTClient; module Util

	# Converts the response of a RT REST API
	# call to a hash
	def self.response_to_h(resp)
		resp.gsub!(/RT\/\d+\.\d+\.\d+\s\d{3}\s.*\n\n/,"") # toss the HTTP response
		#resp.gsub!(/\n\n/,"\n") # remove double spacing, TMail stops at a blank line

		# unfold folded fields
		# A newline followed by one or more spaces is treated as a
		# single space
		resp.gsub!(/\n +/, " ")
		
		#replace CF spaces with underscores
		while resp.match(/CF\.\{[\w_ ]*[ ]+[\w ]*\}/) 
			resp.gsub!(/CF\.\{([\w_ ]*)([ ]+)([\w ]*)\}/, 'CF.{\1_\3}')
		end
		return {:error => resp, }  if resp =~ /does not exist./

		# convert fields to key value pairs
		ret = {}
		resp.each_line do |ln|
			next unless ln =~ /^.+?:/
			ln_a = ln.split(/:/,2)
			ln_a.map! {|item| item.strip}
			ln_a[0].downcase!
			ret[ln_a[0]] = ln_a[1]
		end

		return ret
	end

	# Helper for composing RT's "forms".  Requires a hash where the
	# keys are field names for an RT form.	If there's a :Text key, the value
	# is modified to insert whitespace on continuation lines.  If there's an
	# :Attachment key, the value is assumed to be a comma-separated list of
	# filenames to attach.	It returns a multipart MIME body complete
	# with boundaries and headers, suitable for an HTTP POST.
	def self.compose(fields) # :doc:
		body = ""
		if fields.class != Hash
			raise "RT_Client.compose requires parameters as a hash."
		end

		# fixup Text field for RFC822 compliance
		if fields.has_key? :Text
			fields[:Text].gsub!(/\n/,"\n ") # insert a space on continuation lines.
		end

		# attachments
		if fields.has_key? :Attachments
			fields[:Attachment] = fields[:Attachments]
			fields.delete :Attachments
		end
		if fields.has_key? :Attachment
			filenames = fields[:Attachment].split(',')
			i = 0
			filenames.each do |v|
				filename = File.basename(v)
				mime_type = MIME::Types.type_for(v)[0]
				i += 1
				param_name = "attachment_#{i.to_s}"
				body << "--#{@boundary}\r\n"
				body << "Content-Disposition: form-data; "
				body << "name=\"#{URI.escape(param_name.to_s)}\"; "
				body << "filename=\"#{URI.escape(filename)}\"\r\n"
				body << "Content-Type: #{mime_type.simplified}\r\n\r\n"
				body << File.read(v) # oh dear, lets hope you have lots of RAM
			end
			# strip paths from filenames
			fields[:Attachment] = filenames.map {|f| File.basename(f)}.join(',') 
		end
		field_array = fields.map { |k,v| "#{k}: #{v}" }
		content = field_array.join("\n") # our form
		# add the form to the end of any attachments
		body << "--#{@boundary}\r\n"
		body << "Content-Disposition: form-data; "
		body << "name=\"content\";\r\n\r\n"
		body << content << "\r\n"
		body << "--#{@boundary}--\r\n"
		body
	end

end; end
