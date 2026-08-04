require "test_helper"

class CompanyTest < ActiveSupport::TestCase
  test "crea empresa con slug y token generados automáticamente" do
    company = Company.create!(name: "Mariachi Sol de México", monthly_fee: 60.0)

    assert_not_nil company.slug
    assert_equal "mariachi-sol-de-mexico", company.slug
    assert_not_nil company.invitation_token
    assert company.active?
  end

  test "garantiza unicidad de slug" do
    Company.create!(name: "Empresa Test", slug: "empresa-test", monthly_fee: 0)
    duplicate = Company.new(name: "Empresa Test 2", slug: "empresa-test", monthly_fee: 0)

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:slug], "has already been taken"
  end

  test "recalcula token de invitación al solicitarlo" do
    company = Company.create!(name: "Empresa Token", monthly_fee: 0)
    old_token = company.invitation_token
    company.regenerate_token!

    assert_not_equal old_token, company.invitation_token
  end
end
