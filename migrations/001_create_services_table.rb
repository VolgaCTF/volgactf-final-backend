::Sequel.migration do
  up do
    create_table(:services) do
      primary_key :id
      String :name, size: 50, null: false, unique: true
      String :alias, size: 50, null: false, unique: true
      String :vulnbox_endpoint_code, size: 512, null: false
      String :checker_endpoint, size: 256, null: false
      TrueClass :attack_priority, null: false, default: false
      Integer :poll_grace_period, null: false, default: 0
      Integer :award_defence_after, null: true, default: nil
      TrueClass :enabled, null: false, default: false
      Integer :enable_in, null: true, default: nil
      Integer :disable_in, null: true, default: nil
      Integer :lock_version, null: false, default: 0
    end
  end

  down do
    drop_table(:services)
  end
end
