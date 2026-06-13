module Main (main) where

import Domain.AuditLog.AuditIngestionSpec qualified
import Domain.AuditLog.AuditRecordFactorySpec qualified
import Domain.AuditLog.AuditRecordSpec qualified
import Domain.AuditLog.ReasonCodeSpec qualified
import Domain.AuditLog.ReasonSourceSpec qualified
import Domain.AuditLog.ResultSpec qualified
import Domain.AuditLog.ServicePolicySpec qualified
import Domain.AuditLog.SpecificationSpec qualified
import Domain.AuditLog.StatusSpec qualified
import Domain.AuditLogSpec qualified
import Infrastructure.Repository.FirestoreAuditIngestionRepositorySpec qualified
import Infrastructure.Repository.FirestoreAuditRecordRepositorySpec qualified
import Infrastructure.Repository.IntegrationSpec qualified
import Test.Hspec (hspec)
import UseCase.QueryAuditLogByIdentifierSpec qualified
import UseCase.QueryAuditLogsSpec qualified
import UseCase.RecordAuditFromSourceEventSpec qualified

main :: IO ()
main =
  hspec $ do
    Domain.AuditLogSpec.spec
    Domain.AuditLog.ReasonCodeSpec.spec
    Domain.AuditLog.ReasonSourceSpec.spec
    Domain.AuditLog.ResultSpec.spec
    Domain.AuditLog.StatusSpec.spec
    Domain.AuditLog.AuditIngestionSpec.spec
    Domain.AuditLog.AuditRecordSpec.spec
    Domain.AuditLog.AuditRecordFactorySpec.spec
    Domain.AuditLog.SpecificationSpec.spec
    Domain.AuditLog.ServicePolicySpec.spec
    UseCase.RecordAuditFromSourceEventSpec.spec
    UseCase.QueryAuditLogsSpec.spec
    UseCase.QueryAuditLogByIdentifierSpec.spec
    Infrastructure.Repository.FirestoreAuditRecordRepositorySpec.spec
    Infrastructure.Repository.FirestoreAuditIngestionRepositorySpec.spec
    Infrastructure.Repository.IntegrationSpec.spec
