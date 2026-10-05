import {
  Body,
  Controller,
  Get,
  Param,
  ParseUUIDPipe,
  Post,
  Req,
} from "@nestjs/common";
import { AuthRequest, Roles } from "../auth/auth";
import { PackagesService } from "./packages.service";
import * as D from "../studio/dto";

@Controller()
export class PackagesController {
  constructor(private service: PackagesService) {}

  @Get("packages/products")
  packageProducts() {
    return this.service.packageProducts();
  }

  @Roles("ADMIN")
  @Get("admin/packages/products")
  allPackageProducts() {
    return this.service.allPackageProducts();
  }

  @Roles("ADMIN")
  @Post("admin/packages/products")
  createPackageProduct(@Body() d: D.PackageProductDto) {
    return this.service.createPackageProduct(d);
  }

  @Roles("MEMBER")
  @Post("packages/purchase")
  purchasePackage(@Req() r: AuthRequest, @Body() d: D.PurchasePackageDto) {
    return this.service.purchasePackage(r.user, d);
  }

  @Get("packages")
  memberPackages(@Req() r: AuthRequest) {
    return this.service.memberPackages(r.user);
  }

  @Roles("ADMIN")
  @Post("packages/:id/approve")
  approvePackage(@Param("id", ParseUUIDPipe) id: string) {
    return this.service.reviewPackagePurchase(id, true);
  }

  @Roles("ADMIN")
  @Post("packages/:id/reject")
  rejectPackage(
    @Param("id", ParseUUIDPipe) id: string,
    @Body() d: D.ReasonDto,
  ) {
    return this.service.reviewPackagePurchase(id, false, d.reason);
  }
}
