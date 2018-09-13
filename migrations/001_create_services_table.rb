::Sequel.migration do
  up do
    create_table(:services) do
      primary_key :id
      String :name, size: 50, null: false, unique: true
      String :alias, size: 50, null: false, unique: true
      String :hostmask, size: 15, null: false
      String :checker_endpoint, size: 256, null: false
      TrueClass :attack_priority, null: false, default: false
      Integer :award_defence_after, null: true, default: nil
      TrueClass :enabled, null: false, default: false
      Integer :enable_in, null: true, default: nil
      Integer :disable_in, null: true, default: nil
    end
  end

  down do
    drop_table(:services)
  end
end
