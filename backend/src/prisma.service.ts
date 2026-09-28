import {
  Injectable,
  OnModuleInit,
  OnModuleDestroy,
  ConflictException,
} from "@nestjs/common";
import { Prisma, PrismaClient } from "@prisma/client";
@Injectable()
export class PrismaService
  extends PrismaClient
  implements OnModuleInit, OnModuleDestroy
{
  async onModuleInit() {
    await this.$connect();
  }
  async onModuleDestroy() {
    await this.$disconnect();
  }
  async serial<T>(
    work: (tx: Prisma.TransactionClient) => Promise<T>,
  ): Promise<T> {
    for (let n = 0; n < 4; n++) {
      try {
        return await this.$transaction(work, {
          isolationLevel: Prisma.TransactionIsolationLevel.Serializable,
        });
      } catch (e) {
        if (
          e instanceof Prisma.PrismaClientKnownRequestError &&
          e.code === "P2034"
        ) {
          if (n === 3)
            throw new ConflictException(
              "Another booking changed this session. Please try again.",
            );
        } else throw e;
      }
    }
    throw new ConflictException("Please try again.");
  }
}
