require 'test/unit'
require 'rt/util'

class UtilTest < Test::Unit::TestCase
	def test_response_to_h
		resp = File.read "test/cases/rest-reply-show.txt"
		val = RTClient::Util.response_to_h(resp)
		puts val.inspect
		assert_equal 24, val.size
	end
end
