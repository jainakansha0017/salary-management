# index_current_compensations_on_base_amount was added for the directory's
# sort-by-pay, on the assumption that the sort would walk it in order. It never
# did. Measured against the full seed, that query is a top-N heapsort over the
# joined population whether or not the index exists — 10.2ms with, 9.9ms once
# the directory moved to selecting compensation by effective date — and
# pg_stat_user_indexes reports zero scans over the database's whole lifetime,
# including the seed.
#
# Since the directory now reads `effective_on(date)` rather than
# `effective_to IS NULL`, the partial predicate cannot match the query at all.
# What is left is 312 kB kept current on every compensation write, and a claim
# in the schema that pay is indexed for sorting when it is not.
#
# Reversible: `down` restores it exactly, should a future access pattern — a
# covering index for a top-earners report, say — actually want it.
class RemoveUnusedCurrentCompensationAmountIndex < ActiveRecord::Migration[7.1]
  def change
    remove_index :compensations, :amount_base_minor,
                 where: "effective_to IS NULL",
                 name: "index_current_compensations_on_base_amount"
  end
end
