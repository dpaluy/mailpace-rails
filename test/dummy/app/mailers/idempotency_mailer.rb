class IdempotencyMailer < ApplicationMailer
  default from: 'notifications@example.com',
          to: 'fake@sdfasdfsdaf.com'

  def hyphenated_key
    headers['Idempotency-Key'] = 'hyphen-123'
    mail(subject: 'Hello', body: 'Hi')
  end

  def snake_case_key
    headers['idempotency_key'] = 'snake-123'
    mail(subject: 'Hello', body: 'Hi')
  end

  def no_key
    mail(subject: 'Hello', body: 'Hi')
  end
end
