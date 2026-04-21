require 'test_helper'

class Mailpace::Rails::Test < ActiveSupport::TestCase
  setup do
    ActionMailer::Base.delivery_method = :mailpace
    ActionMailer::Base.mailpace_settings = { api_token: 'api_token' }

    stub_request(:post, 'https://app.mailpace.com/api/v1/send')
      .to_return(
        body: { "status": 'queued', "id": 1 }.to_json,
        headers: { content_type: 'application/json' },
        status: 200
      )

    @test_email = TestMailer.welcome_email
  end

  test 'truth' do
    assert_kind_of Module, Mailpace::Rails
  end

  test 'api token can be set' do
    ActionMailer::Base.mailpace_settings = { api_token: 'api-token' }
    assert_equal ActionMailer::Base.mailpace_settings[:api_token], 'api-token'
  end

  test 'raises ArgumentError if no api token set' do
    ActionMailer::Base.mailpace_settings = {}
    assert_raise(ArgumentError) { @test_email.deliver! }
  end

  test 'raises ArgumentError if no from address in email' do
    t = TestMailer.welcome_email
    t.from = nil
    assert_raise(ArgumentError) { t.deliver! }
  end

  test 'raises ArgumentError if no to address in email' do
    t = TestMailer.welcome_email
    t.to = nil
    assert_raise(ArgumentError) { t.deliver! }
  end

  test 'send basic emails to endpoint' do
    @test_email.deliver!

    assert_requested(
      :post, 'https://app.mailpace.com/api/v1/send',
      times: 1
    )
  end

  test 'forwards Idempotency-Key header when set on the mail' do
    IdempotencyMailer.hyphenated_key.deliver!

    assert_requested(
      :post, 'https://app.mailpace.com/api/v1/send',
      times: 1
    ) do |req|
      req.headers['Idempotency-Key'] == 'hyphen-123'
    end
  end

  test 'forwards Idempotency-Key header when set with snake_case name' do
    IdempotencyMailer.snake_case_key.deliver!

    assert_requested(
      :post, 'https://app.mailpace.com/api/v1/send',
      times: 1
    ) do |req|
      req.headers['Idempotency-Key'] == 'snake-123'
    end
  end

  test 'does not send Idempotency-Key header when mail has none' do
    IdempotencyMailer.no_key.deliver!

    assert_requested(
      :post, 'https://app.mailpace.com/api/v1/send',
      times: 1
    ) do |req|
      !req.headers.key?('Idempotency-Key')
    end
  end

  test 'supports multiple attachments' do
    t = TestMailer.welcome_email
    t.attachments['logo.png'] = File.read("#{Dir.pwd}/test/logo.png")
    t.attachments['l2.png'] = File.read("#{Dir.pwd}/test/logo.png")

    t.deliver!

    assert_requested(
      :post, 'https://app.mailpace.com/api/v1/send',
      times: 1
    ) do |req|
      attachments = JSON.parse(req.body)['attachments']
      attachments[0]['name'] == 'logo.png' && attachments[1]['name'] == 'l2.png'
    end
  end

  test 'supports custom mime types' do
    t = TestMailer.welcome_email
    t.attachments['logo.png'] = {
      mime_type: 'custom/type',
      content: File.read("#{Dir.pwd}/test/logo.png")
    }
    t.deliver!

    assert_requested(
      :post, 'https://app.mailpace.com/api/v1/send',
      times: 1
    ) do |req|
      JSON.parse(req.body)['attachments'][0]['content_type'] == 'custom/type'
    end
  end

  test 'supports full names in the from address' do
    t = FullNameMailer.full_name_email
    t.deliver!

    assert_requested(
      :post, 'https://app.mailpace.com/api/v1/send',
      times: 1
    ) do |req|
      JSON.parse(req.body)['from'] == 'My Full Name <notifications@example.com>'
    end
  end

  test 'supports full names in the to address' do
    t = FullNameMailer.full_name_email
    t.deliver!

    assert_requested(
      :post, 'https://app.mailpace.com/api/v1/send',
      times: 1
    ) do |req|
      JSON.parse(req.body)['to'] == 'Recipient Full Name <fake@sdfasdfsdaf.com>'
    end
  end

  test 'supports single tag' do
    t = TagMailer.single_tag
    t.deliver!

    assert_requested(
      :post, 'https://app.mailpace.com/api/v1/send',
      times: 1
    ) do |req|
      JSON.parse(req.body)['tags'] == 'test tag'
    end
  end

  test 'supports array of tags tag' do
    t = TagMailer.multi_tag
    t.deliver!

    assert_requested(
      :post, 'https://app.mailpace.com/api/v1/send',
      times: 1
    ) do |req|
      JSON.parse(req.body)['tags'] == "['test tag', 'another-tag']"
    end
  end

  test 'does not send tags if tags not supplied' do
    t = TestMailer.welcome_email
    t.deliver!

    assert_requested(
      :post, 'https://app.mailpace.com/api/v1/send',
      times: 1
    ) do |req|
      JSON.parse(req.body)['tags'].nil?
    end
  end

  test 'supports List-Unsubscribe header' do
    t = ListUnsubscribeMailer.unsubscribe
    t.deliver!

    assert_requested(
      :post, 'https://app.mailpace.com/api/v1/send',
      times: 1
    ) do |req|
      JSON.parse(req.body)['list_unsubscribe'] == 'test list-unsubscribe'
    end
  end

  test 'deliver! returns the API response' do
    t = TestMailer.welcome_email
    res = t.deliver!
    assert_equal res['id'], 1
  end

  # See https://github.com/mikel/mail/blob/22a7afc23f253319965bf9228a0a430eec94e06d/lib/mail/fields/reply_to_field.rb
  test 'supports reply to' do
    t = TestMailer.welcome_email
    t.reply_to = 'Reply To Name <reply@test.com>'
    t.deliver!

    assert_requested(
      :post, 'https://app.mailpace.com/api/v1/send',
      times: 1
    ) do |req|
      JSON.parse(req.body)['replyto'] == 'Reply To Name <reply@test.com>'
    end
  end

  test 'supports complex cc and bcc entries' do
    t = ComplexMailer.complex_email
    t.deliver!

    assert_requested(
      :post, 'https://app.mailpace.com/api/v1/send',
      times: 1
    ) do |req|
      JSON.parse(req.body)['cc'] == 'test@test.com,full name cc <test2@test.com>' &&
        JSON.parse(req.body)['bcc'] == 'full name bcc <test2@test.com>'
    end
  end

  test 'raises DeliveryError if response is not 200' do
    stub_request(:post, 'https://app.mailpace.com/api/v1/send')
      .to_return(
        body: { error: 'contains a blocked address' }.to_json,
        headers: { content_type: 'application/json' },
        status: 400
      )

    t = TestMailer.welcome_email

    error = assert_raise(Mailpace::DeliveryError) do
      t.deliver!
    end

    assert_equal 'MAILPACE Error: contains a blocked address', error.message
    assert_equal 400, error.status_code
    assert_equal 'contains a blocked address', error.provider_error
    assert_equal({ 'error' => 'contains a blocked address' }, error.parsed_response)
    assert error.client_error?
    assert error.blocked_address?
    refute error.server_error?
  end

  test 'DeliveryError keeps normal exception construction compatibility' do
    assert_instance_of Mailpace::DeliveryError, Mailpace::DeliveryError.new

    assert_raise(Mailpace::DeliveryError) do
      raise Mailpace::DeliveryError
    end
  end

  test 'DeliveryError predicates fall back to existing message text' do
    error = Mailpace::DeliveryError.new('MAILPACE Error: contains a blocked address')

    assert error.blocked_address?
  end

  test 'DeliveryError exposes response metadata for provider concurrency errors' do
    stub_request(:post, 'https://app.mailpace.com/api/v1/send')
      .to_return(
        body: { error: 'Concurrent requests detected' }.to_json,
        headers: { content_type: 'application/json' },
        status: 409
      )

    error = assert_raise(Mailpace::DeliveryError) do
      TestMailer.welcome_email.deliver!
    end

    assert_equal 'MAILPACE Error: Concurrent requests detected', error.message
    assert_equal 409, error.status_code
    assert_equal 'Concurrent requests detected', error.provider_error
    assert_equal({ 'error' => 'Concurrent requests detected' }, error.parsed_response)
    assert error.concurrency_rejection?
    assert error.client_error?
    refute error.server_error?
  end

  test 'DeliveryError provider_error can come from errors response key' do
    stub_request(:post, 'https://app.mailpace.com/api/v1/send')
      .to_return(
        body: { errors: ['first failure', 'second failure'] }.to_json,
        headers: { content_type: 'application/json' },
        status: 403
      )

    error = assert_raise(Mailpace::DeliveryError) do
      TestMailer.welcome_email.deliver!
    end

    assert_equal 'MAILPACE Error: first failure, second failure', error.message
    assert_equal 403, error.status_code
    assert_equal 'first failure, second failure', error.provider_error
    assert_equal({ 'errors' => ['first failure', 'second failure'] }, error.parsed_response)
    assert error.client_error?
  end

  test 'DeliveryError falls back to HTTP status for non-json responses' do
    stub_request(:post, 'https://app.mailpace.com/api/v1/send')
      .to_return(
        body: 'Gateway timeout with raw provider details',
        headers: { content_type: 'text/plain' },
        status: 504
      )

    error = assert_raise(Mailpace::DeliveryError) do
      TestMailer.welcome_email.deliver!
    end

    assert_equal 'MAILPACE Error: HTTP 504', error.message
    assert_equal 504, error.status_code
    assert_nil error.provider_error
    assert_nil error.parsed_response
    assert error.server_error?
    refute error.client_error?
    refute_respond_to error, :raw_response
  end

  test 'supports in-reply-to' do
    t = TestMailer.welcome_email
    t.in_reply_to = '<message-id@test.com>'
    t.deliver!

    assert_requested(
      :post, 'https://app.mailpace.com/api/v1/send',
      times: 1
    ) do |req|
      JSON.parse(req.body)['inreplyto'] == '<message-id@test.com>'
    end
  end

  test 'supports single references' do
    t = TestMailer.welcome_email
    t.references = '<message-id@test.com>'
    t.deliver!

    assert_requested(
      :post, 'https://app.mailpace.com/api/v1/send',
      times: 1
    ) do |req|
      JSON.parse(req.body)['references'] == '<message-id@test.com>'
    end
  end

  test 'supports multiple references' do
    t = TestMailer.welcome_email
    t.references = '<message-id@test.com> <message-id2@test.com>'
    t.deliver!

    assert_requested(
      :post, 'https://app.mailpace.com/api/v1/send',
      times: 1
    ) do |req|
      JSON.parse(req.body)['references'] == '<message-id@test.com> <message-id2@test.com>'
    end
  end

  test 'supports setting idempotency key directly' do
    t = TestMailer.welcome_email
    t.header['idempotency_key'] = 'example key'
    t.deliver!

    assert_requested(
      :post, 'https://app.mailpace.com/api/v1/send',
      times: 1
    ) do |req|
      req.headers['Idempotency-Key'] == 'example key'
    end
  end

  test 'supports email with idempotency key set' do
    t = IdempotentMailer.idempotent_email
    t.deliver!

    assert_requested(
      :post, 'https://app.mailpace.com/api/v1/send',
      times: 1
    ) do |req|
      req.headers['Idempotency-Key'] == 'example key'
    end
  end

  test 'idempotency key is not in the request if it is not set in the email' do
    @test_email.deliver!

    assert_requested(
      :post, 'https://app.mailpace.com/api/v1/send',
      times: 1
    ) do |req|
      req.headers['Idempotency-Key'].nil?
    end
  end

  test 'supports text-only emails' do
    t = PlaintextMailer.plain_only_email
    t.references = '<message-id@test.com> <message-id2@test.com>'
    t.deliver!

    assert_requested(
      :post, 'https://app.mailpace.com/api/v1/send',
      times: 1
    ) do |req|
      JSON.parse(req.body)['htmlbody'].nil? &&
        JSON.parse(req.body)['textbody'] == "test text only\n"
    end
  end

  test 'supports html-only emails' do
    t = HtmlMailer.html_only_email
    t.deliver!

    assert_requested(
      :post, 'https://app.mailpace.com/api/v1/send',
      times: 1
    ) do |req|
      !JSON.parse(req.body)['htmlbody'].nil? &&
        JSON.parse(req.body)['textbody'].nil?
    end
  end

  test 'supports multipart emails without a text part' do
    t = MultipartMailer.no_text_email
    assert t.multipart?
    t.deliver!

    assert_requested(
      :post, 'https://app.mailpace.com/api/v1/send',
      times: 1
    ) do |req|
      !JSON.parse(req.body)['htmlbody'].nil? &&
        JSON.parse(req.body)['textbody'].nil?
    end
  end

  test 'supports multipart emails without an html part' do
    t = MultipartMailer.no_html_email
    assert t.multipart?
    t.deliver!

    assert_requested(
      :post, 'https://app.mailpace.com/api/v1/send',
      times: 1
    ) do |req|
      JSON.parse(req.body)['htmlbody'].nil? &&
        !JSON.parse(req.body)['textbody'].nil?
    end
  end
end
