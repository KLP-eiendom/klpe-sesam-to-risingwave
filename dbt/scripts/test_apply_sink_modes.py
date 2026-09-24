import pytest
from apply_sink_modes import get_group_for_sink, get_desired_mode, SINK_GROUPS


class TestGetGroupForSink:
    def test_forvalter_simple(self):
        assert get_group_for_sink('snk_dokument_forvalter') == 'FORVALTER_SINK_MODE'

    def test_forvalter_compound(self):
        assert get_group_for_sink('snk_contract_details_forvalter') == 'FORVALTER_SINK_MODE'

    def test_kundeportal(self):
        assert get_group_for_sink('snk_ticket_kundeportal') == 'KUNDEPORTAL_SINK_MODE'

    def test_kundeportal_compound(self):
        assert get_group_for_sink('snk_garanti_kundeportal') == 'KUNDEPORTAL_SINK_MODE'

    def test_superoffice(self):
        assert get_group_for_sink('snk_kredittvurdering_superoffice') == 'SUPEROFFICE_SINK_MODE'

    def test_superoffice_compound(self):
        assert get_group_for_sink('snk_prosjekt_juridiskselskap_superoffice') == 'SUPEROFFICE_SINK_MODE'

    def test_bq(self):
        assert get_group_for_sink('snk_customer_bq') == 'BQ_SINK_MODE'

    def test_bqeos(self):
        assert get_group_for_sink('snk_bygg_bqeos') == 'BQ_SINK_MODE'

    def test_leko_suffix(self):
        assert get_group_for_sink('snk_customer_leko') == 'LEKO_SINK_MODE'

    def test_leko_prefix(self):
        assert get_group_for_sink('snk_leko_kontrakt') == 'LEKO_SINK_MODE'

    def test_powerapp(self):
        assert get_group_for_sink('snk_user_powerapp') == 'POWERAPP_SINK_MODE'

    def test_findable(self):
        assert get_group_for_sink('snk_bygg_findable') == 'FINDABLE_SINK_MODE'


    def test_miljoprofil(self):
        assert get_group_for_sink('snk_bygg_miljoprofil') == 'MILJOPROFIL_SINK_MODE'

    def test_miljoprofil_compound(self):
        assert get_group_for_sink('snk_energycustomerconsumption_miljoprofil') == 'MILJOPROFIL_SINK_MODE'

    def test_dalux(self):
        assert get_group_for_sink('snk_leverandor_dalux') == 'DALUX_SINK_MODE'

    def test_unknown_returns_none(self):
        assert get_group_for_sink('snk_something_unknown') is None


class TestGetDesiredMode:
    def test_paused_when_set(self):
        env = {'FORVALTER_SINK_MODE': 'paused'}
        assert get_desired_mode('FORVALTER_SINK_MODE', env) == 'paused'

    def test_running_when_set(self):
        env = {'FORVALTER_SINK_MODE': 'running'}
        assert get_desired_mode('FORVALTER_SINK_MODE', env) == 'running'

    def test_running_when_absent(self):
        assert get_desired_mode('FORVALTER_SINK_MODE', {}) == 'running'

    def test_running_when_group_is_none(self):
        assert get_desired_mode(None, {'FORVALTER_SINK_MODE': 'paused'}) == 'running'

    def test_case_insensitive_value(self):
        env = {'FORVALTER_SINK_MODE': 'PAUSED'}
        assert get_desired_mode('FORVALTER_SINK_MODE', env) == 'paused'
