require 'aws-sdk-s3'

Aws.config[:ssl_verify_peer] = false

module RedmineS3
  module Connection
    @@conn = nil
    @@s3_options = {
      access_key_id:      nil,
      secret_access_key:  nil,
      bucket:             nil,
      folder:             '',
      endpoint:           nil,
#      port:               nil,
#      ssl:                nil,
      private:            false,
      expires:            nil,
#      secure:             false,
      proxy:              false,
      thumb_folder:       'tmp',
      region:             nil,
    }

    class << self
      def bucket
        conn.bucket(bucket_name)
      end

      def create_bucket
        bucket = self.bucket
        bucket.create unless bucket.exists?
      end

      def folder
        str = @@s3_options[:folder]
        (
          if str.present?
            str.match(/\S+\//) ? str : "#{str}/"
          else
            ''
          end
        ).presence
      end

      def proxy?
        @@s3_options[:proxy]
      end

      def thumb_folder
        str = @@s3_options[:thumb_folder]
        (
          if str.present?
            str.match(/\S+\//) ? str : "#{str}/"
          else
            'tmp/'
          end
        ).presence
      end

      def put(disk_filename, original_filename, data, content_type='application/octet-stream', target_folder = self.folder)
        options = {
          body:                 data,
          content_disposition:  "inline; filename=#{ERB::Util.url_encode(original_filename)}",
        }
        options[:acl] = 'public-read' unless private?
        options[:content_type] = content_type if content_type

        object = object(disk_filename, target_folder)
        object.put(options)
      end

      def delete(filename, target_folder = self.folder)
        object = object(filename, target_folder)
        object.delete
      end

      def object_url(filename, target_folder = self.folder)
        object = object(filename, target_folder)
        if private?
          options = {}
          options[:expires_in] = expires unless expires.nil?
          object.presigned_url(:get, options)
        else
          object.public_url
        end
      end

      def get(filename, target_folder = self.folder)
        object = object(filename, target_folder)
        object.reload unless object.data_loaded?
        object.data
      end

# private

      def establish_connection
        load_options unless @@s3_options[:access_key_id] && @@s3_options[:secret_access_key]
        options = {
          access_key_id:      @@s3_options[:access_key_id],
          secret_access_key:  @@s3_options[:secret_access_key]
        }
        if endpoint.present?
          options[:endpoint] = endpoint
        elsif region.present?
          options[:region] = region
        end
        @@conn = Aws::S3::Resource.new(options)
      end

      def load_options
        file = ERB.new( File.read(File.join(Rails.root, 'config', 's3.yml')) ).result
        YAML::load( file )[Rails.env].each do |key, value|
          @@s3_options[key.to_sym] = value
        end
      end

      def conn
        @@conn || establish_connection
      end

      def bucket_name
        load_options unless @@s3_options[:bucket]
        @@s3_options[:bucket]
      end

      def endpoint
        @@s3_options[:endpoint]
      end

      def region
        @@s3_options[:region]
      end

      def expires
        @@s3_options[:expires]
      end

      def private?
        @@s3_options[:private]
      end

      def object(filename, target_folder = self.folder)
        object_nm = File.join([target_folder.presence, filename.presence].compact)
        bucket.object(object_nm)
      end
    end

    private_class_method  :establish_connection, :load_options, :conn, :bucket_name, :endpoint, :region, :expires, :private?, :object
  end
end
