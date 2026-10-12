import unittest
import json
import tempfile
from pathlib import Path
from unittest.mock import patch
from types import SimpleNamespace
from decimal import Decimal
import state_development_collection as collection
from state_development_collection import DocumentHTML, blocked
from state_development_normalize import rupees, source_projects,monthly_accounts,assam_sector_expenditure,telangana_budget

class StateEvidenceRules(unittest.TestCase):
    def test_explicit_index_refresh_preserves_both_originals_and_earlier_receipt(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);base=root/'data/acquisition/state-development'
            state={'code':'28','name':'Andhra Pradesh','sources':[{'id':'budget-index','kind':'budget_index','label':'Official budget index','url':'https://example.invalid/budget'}]}
            (base/'plan.json').parent.mkdir(parents=True);(base/'plan.json').write_text(json.dumps({'states':[state]}))
            originals=[b'<p>First official edition</p>',b'<p>Revised official edition</p>']
            def download(command,**kwargs):
                Path(command[command.index('--dump-header')+1]).write_text('HTTP/1.1 200 OK\n')
                Path(command[command.index('-o')+1]).write_bytes(originals.pop(0))
                return SimpleNamespace(returncode=0,stderr='')
            with patch.object(collection,'ROOT',root),patch.object(collection,'BASE',base),patch.object(collection.subprocess,'run',side_effect=download) as request:
                collection.collect(state)
                collection.collect(state)
                self.assertEqual(request.call_count,1)
                collection.collect(state,refresh_indexes=True)
                self.assertEqual(request.call_count,2)
                cp=json.loads((base/'28/checkpoint.json').read_text())
                self.assertEqual(len(cp['documents']),1)
                self.assertEqual(len(cp['previousEditions']),1)
                prior=cp['previousEditions'][0];current=cp['documents'][0]
                self.assertNotEqual(prior['sha256'],current['sha256'])
                self.assertEqual((root/prior['original']).read_bytes(),b'<p>First official edition</p>')
                self.assertEqual((root/current['original']).read_bytes(),b'<p>Revised official edition</p>')
                self.assertFalse(cp['completeCoverage'])

    def test_exact_amounts_and_missing_not_zero(self):
        self.assertEqual(rupees('34,978.14','crore'),'349781400000.00')
        self.assertEqual(rupees('-0.01','crore'),'-100000.00')
        self.assertIsNone(rupees('-','crore'))
        self.assertEqual(rupees('0.00','lakh'),'0.00')
        with self.assertRaises(ValueError): rupees('0.001','rupee')

    def test_awarded_work_is_not_assigned_a_payment_or_year(self):
        doc={'sha256':'a'*64,'stateCode':'28','url':'https://example.invalid/awards','retrievedAt':'2026-10-12T00:00:00Z'}
        rows=source_projects(doc,{'tables':[{'table':1,'rows':[['S.No','Tender ID','Description','Successful Bidder'],['1','1234','School construction','Documented Contractor Ltd']]}]})
        self.assertEqual(rows[0]['sourceProjectId'],'1234')
        self.assertIsNone(rows[0]['paymentAmountRupees'])
        self.assertIsNone(rows[0]['financialYear'])
        self.assertIsNone(rows[0]['awardDate'])

    def test_html_preserves_separate_financial_rows_without_scripts(self):
        p=DocumentHTML();p.feed('<script>secret()</script><table><tr><th>Measure</th><th>Amount</th></tr><tr><td>Budget</td><td>20.00</td></tr><tr><td>Expenditure</td><td>5.00</td></tr></table><a href="a.pdf">Annual report</a>')
        self.assertNotIn('secret()',p.text)
        self.assertEqual(len(p.tables[0]),3)
        self.assertEqual(p.links[0]['href'],'a.pdf')
        self.assertFalse(blocked('Enter CAPTCHA to search tenders'))
        self.assertTrue(blocked('Request rejected. Access denied.'))

    def test_nested_procurement_layout_retains_the_actual_tender_grid(self):
        p=DocumentHTML();p.feed('<table><tr><td>Page layout<table><tr><th>Tender Title</th><th>Reference No</th></tr><tr><td>School construction</td><td>WORK-2026-1</td></tr></table></td></tr></table>')
        grid=next(t for t in p.tables if t[0]==['Tender Title','Reference No'])
        self.assertEqual(grid[1],['School construction','WORK-2026-1'])

    def test_monthly_actuals_keep_their_cutoff_and_reject_column_misalignment(self):
        doc={'sha256':'a'*64,'stateCode':'10','url':'https://example.invalid/accounts','retrievedAt':'2026-10-12T00:00:00Z'}
        rows=[{'line':1,'text':'ACCOUNTS AT A GLANCE (At the end of March 2026) (₹ in Crores)'},{'line':2,'text':'5. Capital Expenditure (a+b)      100.00    80.00    80.00    70.00'}]
        result=monthly_accounts(doc,{'pages':[{'lines':rows}]})
        self.assertEqual(result[0]['financialYear'],'2025-2026')
        self.assertEqual(result[0]['periodEnd'],'2026-03-31')
        self.assertEqual(result[0]['amountRupees'],'800000000.00')
        self.assertEqual(result[0]['classification'],'broad_financial_context')
        rows[1]['text']='5. Capital Expenditure (a+b)      100.00    80.00    5.00    70.00'
        self.assertEqual(monthly_accounts(doc,{'pages':[{'lines':rows}]}),[])

    def test_assam_actual_column_is_requested_year_lakhs_with_production_caveat(self):
        doc={'sha256':'a'*64,'url':'https://testfin.assam.gov.in/report','retrievedAt':'2026-10-12T00:00:00Z'}
        lines=[{'line':1,'text':'ABSTRACT REPORT OF STATE EXPENDITURE - 2025-26 Amounts in Lakhs 2025-04-01 to 2026-03-31'},
               {'line':2,'text':'REVENUE ACCOUNT'},{'line':3,'text':'B. SOCIAL SERVICES'},
               {'line':4,'text':'(a) Education      100.00 110.00 90.00 95.25 95.25 86.59 5.83 90.00'}]
        result=assam_sector_expenditure(doc,{'pages':[{'page':1,'lines':lines}]})
        self.assertEqual(result[0]['amountRupees'],'9525000.00')
        self.assertEqual(result[0]['sourceOriginalBudget'],'100.00')
        self.assertEqual(result[0]['reviewStatus'],'awaiting_production_source_confirmation')
        lines[0]['text']=lines[0]['text'].replace('Lakhs','Crores')
        with self.assertRaises(ValueError): assam_sector_expenditure(doc,{'pages':[{'page':1,'lines':lines}]})

    def test_monthly_supplementary_and_split_headers_preserve_fiscal_cutoff(self):
        doc={'sha256':'b'*64,'stateCode':'12','url':'https://example.invalid/mki','retrievedAt':'2026-10-12T00:00:00Z'}
        for title,scope,end in [
            ('At the end of March (S), 2026','Budget Estimates 2025-26','2026-03-31'),
            ('At the end of March-2026','Budget Estimates 2025-26','2026-03-31'),
            ('As at the end of March (P)','Budget Estimates 2025-26 Actuals up to March (P) 2026','2026-03-31'),
            ('At the end of 4, 2026','Budget Estimates 2026-27','2026-04-30')]:
            lines=[{'line':1,'text':f'ACCOUNTS AT A GLANCE ({title}) (in crore) {scope}'},
                   {'line':2,'text':'(5) CAPITAL EXPENDITURE     100.00 20.00 20.00 15.00'}]
            result=monthly_accounts(doc,{'pages':[{'page':1,'lines':lines}]})
            self.assertEqual(result[0]['periodEnd'],end)
            self.assertEqual(result[0]['amountRupees'],'200000000.00')
        lines[0]['text']='ACCOUNTS AT A GLANCE At the end of March (P) (in crore) Budget Estimates 2025-26 and 2026-27'
        self.assertEqual(monthly_accounts(doc,{'pages':[{'page':1,'lines':lines}]}),[])

    def test_telangana_overlapping_tables_are_not_relabelled_as_payments(self):
        def line(n,text): return {'line':n,'text':text}
        pages=[{'page':1,'lines':[line(1,'Budget 2026-27')]},
               {'page':12,'lines':[line(1,'TABLE -7 in Crores Accounts 2023-24 Accounts 2024-25 R.E 2025-26 B.E 2026-27')]+[line(i+2,f'Sector {i}      10.00 20.00 30.00 40.00') for i in range(4)]}]
        for page,start,end in [(15,1,21),(16,21,46),(17,46,70)]:
            pages.append({'page':page,'lines':[line(1,'Table - 10 (Rs.in crore) 2026-27 B.E.')]+[line(i+2,f'{i} Maintenance of Roads      500') for i in range(start,end)]})
        pages.append({'page':18,'lines':[line(1,'Table - 11 (Rs.in crore) Establishment Scheme Grand Total')]+[line(i+2,f'{i} Department {i}      100 200 301') for i in range(1,31)]})
        pages.append({'page':19,'lines':[line(1,'Table - 12 in Crores 2026-27 B.E.')]+[line(i+2,f'{i} Department {i}      50') for i in range(1,29)]})
        doc={'sha256':'a'*64,'url':'https://example.invalid/budget','retrievedAt':'2026-10-12T00:00:00Z'}
        records=telangana_budget(doc,{'pages':pages})
        self.assertEqual(len(records),135)
        self.assertTrue(all(r['measure']=='allocated' for r in records))
        self.assertEqual(records[0]['classification'],'maintenance_or_mixed_requires_review')
        department=next(r for r in records if r['budgetTableScope']=='department_total')
        self.assertEqual(department['printedArithmeticDifferenceCrore'],'1')
        self.assertEqual(department['components'][0]['label'],'Establishment')
        revised=next(r for r in records if r['financialYear']=='2025-2026')
        self.assertEqual(revised['amountRupees'],'300000000.00')
        pages[1]['lines'][0]['text']=pages[1]['lines'][0]['text'].replace('R.E 2025-26','Accounts 2025-26')
        with self.assertRaises(ValueError): telangana_budget(doc,{'pages':pages})

if __name__=='__main__': unittest.main()
