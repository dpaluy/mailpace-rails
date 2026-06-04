require 'action_mailer'
require 'action_mailbox/engine'
require 'httparty'
require 'uri'
require 'json'
require 'mailpace-rails/version'
require 'mailpace-rails/engine' if defined? Rails

module Mailpace
  # MailPace ActionMailer delivery method
  class DeliveryMethod
    attr_accessor :settings

    def initialize(values)
      check_api_token(values)
      self.settings = { return_response: true }.merge!(values)
    end

    def deliver!(mail)
      if mail.multipart?
        htmlbody = mail.html_part&.body&.decoded
        textbody = mail.text_part&.body&.decoded
      elsif mail.mime_type == "text/plain"
        textbody = mail.body.to_s
      else
        htmlbody = mail.body.to_s
      end

      check_delivery_params(mail)
      result = HTTParty.post(
        'https://app.mailpace.com/api/v1/send',
        body: {
          from: address_list(mail.header[:from])&.addresses&.first.to_s,
          to: address_list(mail.header[:to])&.addresses&.join(','),
          subject: mail.subject,
          htmlbody: htmlbody,
          textbody: textbody,
          cc: address_list(mail.header[:cc])&.addresses&.join(','),
          bcc: address_list(mail.header[:bcc])&.addresses&.join(','),
          replyto: address_list(mail.header[:reply_to])&.addresses&.join(','),
          inreplyto: mail.header['In-Reply-To'].to_s,
          references: mail.header['References'].to_s,
          list_unsubscribe: mail.header['list_unsubscribe'].to_s,
          attachments: format_attachments(mail.attachments),
          tags: mail.header['tags'].to_s
        }.delete_if { |_key, value| value.blank? }.to_json,
        headers: build_headers(mail)
      )

      handle_response(result)
    end

    private

    def build_headers(mail)
      headers = {
        'User-Agent' => "MailPace Rails Gem v#{Mailpace::Rails::VERSION}",
        'Accept' => 'application/json',
        'Content-Type' => 'application/json',
        'Mailpace-Server-Token' => settings[:api_token]
      }

      idempotency_key = extract_idempotency_key(mail)
      headers['Idempotency-Key'] = idempotency_key if idempotency_key.present?

      headers
    end

    def extract_idempotency_key(mail)
      ['Idempotency-Key', 'idempotency_key'].each do |header_name|
        idempotency_key = mail.header[header_name]&.to_s
        return idempotency_key if idempotency_key.present?
      end

      nil
    end

    def check_api_token(values)
      return if values[:api_token].present?

      raise ArgumentError, 'MailPace API token is not set'
    end

    def check_delivery_params(mail)
      return unless mail.from.nil? || mail.to.nil?

      raise ArgumentError, 'Missing to or from address in email'
    end

    def handle_response(result)
      return result if result.code == 200

      status_code = result.code.to_i
      parsed_response = parsed_response_metadata(result.parsed_response)
      error_message = join_error_messages(parsed_response)
      provider_error = error_message.presence

      raise DeliveryError.new(
        "MAILPACE Error: #{provider_error || "HTTP #{status_code}"}",
        status_code: status_code,
        provider_error: provider_error,
        parsed_response: parsed_response
      )
    end

    def format_attachments(attachments)
      attachments.map do |attachment|
        {
          name: attachment.filename,
          content_type: attachment.mime_type,
          content: Base64.encode64(attachment.body.encoded),
          cid: attachment.content_id
        }.compact
      end
    end

    def address_list(obj)
      if obj&.respond_to?(:element)
        # Mail 2.8+
        obj.element
      else
        # Mail <= 2.7.x
        obj&.address_list
      end
    end

    def join_error_messages(response)
      return '' unless response.is_a?(Hash)

      [response['error'], response['errors']].compact.join(', ')
    end

    def parsed_response_metadata(response)
      response if response.is_a?(Hash)
    end
  end

  class Error < StandardError; end
  class DeliveryError < StandardError
    attr_reader :status_code, :provider_error, :parsed_response

    def initialize(message = nil, status_code: nil, provider_error: nil, parsed_response: nil)
      super(message)
      @status_code = status_code
      @provider_error = provider_error
      @parsed_response = parsed_response
    end

    def concurrency_rejection?
      status_code == 409 || error_text.include?('Concurrent requests detected')
    end

    def server_error?
      status_code.to_i >= 500 && status_code.to_i < 600
    end

    def client_error?
      status_code.to_i >= 400 && status_code.to_i < 500
    end

    def blocked_address?
      error_text.include?('contains a blocked address')
    end

    private

    def error_text
      provider_error.presence || message.to_s
    end
  end

  def self.root
    Pathname.new(File.expand_path(File.join(__dir__, '..')))
  end
end
