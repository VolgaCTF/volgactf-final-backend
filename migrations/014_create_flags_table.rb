::Sequel.migration do
  up do
    create_table(:flags) do
      primary_key :id
      String :flag, size: 40, null: false, index: true, unique: true
      DateTime :created_at, null: false
      DateTime :pushed_at, null: true
      DateTime :expired_at, null: true
      String :label, text: true, null: false
      String :capsule, text: true, null: false
      String :open_data, text: true, null: true

      foreign_key :team_id, :teams, index: true, null: false
      foreign_key :service_id, :services, index: true, null: false
      foreign_key :round_id, :rounds, index: true, null: false
      unique [:team_id, :service_id, :round_id]
    end
  end

  down do
    drop_table(:flags)
  end
end
