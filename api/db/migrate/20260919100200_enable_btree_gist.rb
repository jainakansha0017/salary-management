class EnableBtreeGist < ActiveRecord::Migration[7.1]
  # Exclusion constraints on effective-dated rows need to combine an equality
  # test on a scalar column (which currency pair, which employee) with an
  # overlap test on a range. GiST only handles the range half by default;
  # btree_gist supplies the equality operators for the scalar half.
  def change
    enable_extension "btree_gist"
  end
end
