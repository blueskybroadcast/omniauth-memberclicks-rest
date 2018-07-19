RSpec.describe OmniAuth::Strategies::MemberclicksREST do
  let(:log) { double }
  let(:token_info) { response_fixture('token') }
  let(:user_info) { response_fixture('me') }
  let(:parsed_token_info) { MultiJson.load(token_info) }

  subject { described_class.new('app_id', 'secret') }

  before do
    allow(@app_event).to receive(:logs).and_return(log)
    allow(log).to receive(:create).and_return(true)
  end

  describe '#options' do
    describe '#name' do
      it { expect(subject.options.name).to eq('memberclicks_rest') }
    end

    describe '#client_options' do
      describe '#authorize_url' do
        it { expect(subject.options.client_options.authorize_url).to eq('/oauth/v1/authorize') }
      end

      describe '#custom_field_keys' do
        it { expect(subject.options.client_options.custom_field_keys).to eq([]) }
      end

      describe '#site' do
        it { expect(subject.options.client_options.site).to eq('MUST_BE_PROVIDED') }
      end

      describe '#token_url' do
        it { expect(subject.options.client_options.token_url).to eq('/oauth/v1/token') }
      end

      describe '#user_info_url' do
        it { expect(subject.options.client_options.user_info_url).to eq('/api/v1/profile/me') }
      end
    end
  end

  describe '#info' do
    let(:access_token) do
      {
        token: parsed_token_info['access_token'],
        token_expires: parsed_token_info['expires_in'],
        refresh_token: parsed_token_info['refresh_token']
      }
    end

    before do
      allow(subject).to receive(:access_token).and_return(access_token)
      subject.options.client_options[:site] = 'https://org_id.memberclicks.net'
      subject.options.client_options[:custom_field_keys] = ['[Address | Primary | City]', '[Address | Primary | Zip]']
      stub_request(:get, 'https://org_id.memberclicks.net/api/v1/profile/me')
        .with(headers: { 'Accept' => 'application/json', 'Authorization' => "Bearer #{parsed_token_info['access_token']}" })
        .to_return(status: 200, body: user_info, headers: {})
    end

    context 'first_name' do
      it 'returns first_name' do
        expect(subject.info[:first_name]).to eq 'Lori'
      end
    end

    context 'last_name' do
      it 'returns last_name' do
        expect(subject.info[:last_name]).to eq 'Smith'
      end
    end

    context 'email' do
      it 'returns email' do
        expect(subject.info[:email]).to eq 'lori.smith.work@memberclicks.com'
      end
    end

    context 'username' do
      it 'returns username' do
        expect(subject.info[:username]).to eq 'lsmith1o'
      end
    end

    context 'uid' do
      it 'returns uid as string' do
        expect(subject.info[:uid]).to eq '1001398965'
      end
    end

    context 'member_status' do
      it 'returns member_status' do
        expect(subject.info[:member_status]).to eq 'Active'
      end
    end

    context 'member_type' do
      it 'returns member_type' do
        expect(subject.info[:member_type]).to eq 'Associate'
      end
    end

    context 'custom_fields_data' do
      let(:fields_data) do
        {
          '[address | primary | city]' => 'Clearwater',
          '[address | primary | zip]' => '33758'
        }
      end

      it 'returns custom_fields_data' do
        expect(subject.info[:custom_fields_data]).to eq fields_data
      end
    end
  end
end

def response_fixture(filename)
  IO.read("spec/fixtures/#{filename}.json")
end
